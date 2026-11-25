import CoreFoundation
import Foundation
import IOKit
import IOKit.hid
@_exported import PadWire

public enum PadError: Error, CustomStringConvertible {
    case notFound
    case inputMonitoringDenied
    case busy
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    /// macOS turned a write away, as it does with every write while the Mac is locked: the
    /// pad's channel is part of its keyboard, and a locked Mac keeps keyboards to itself.
    case writesRefused
    case disconnected
    case timeout(Method)
    case rpc(Method, RPCError)
    /// The helper could not do what was asked, and why.
    case helper(String)
    /// macOS would not let the helper hold the pad.
    case holdFailed(IOReturn)

    public var description: String {
        switch self {
        case .notFound: "No Codex Micro found. Plug it in with USB-C or wake it over Bluetooth."
        case .inputMonitoringDenied:
            "macOS blocked access. Allow this program (or the app that launched it) under System Settings > Privacy & Security > Input Monitoring, then try again."
        case .busy: "Another app has the pad open exclusively."
        case let .openFailed(code): "Could not open the pad (IOReturn \(hex(code)))."
        case let .writeFailed(code): "Could not write to the pad (IOReturn \(hex(code)))."
        case .writesRefused: "macOS refused the write to the pad. It refuses every one while the Mac is locked."
        case .disconnected: "The pad disconnected."
        case let .timeout(method): "The pad did not answer \(method.rawValue) within the timeout."
        case let .rpc(method, error): "\(method.rawValue): \(error)"
        case let .helper(reason): "MicroBridge Helper: \(reason)."
        case let .holdFailed(code): "macOS would not let MicroBridge Helper hold the pad (IOReturn \(hex(code)))."
        }
    }
}

extension PadError {
    /// What a failed write means. Seen on 2026-11-21: every write while the Mac was locked
    /// came back 0xE00002E2, and the first came before macOS's lock notice did.
    static func writing(_ result: IOReturn) -> PadError {
        result == ioReturnNotPermitted ? .writesRefused : .writeFailed(result)
    }
}

func hex(_ code: IOReturn) -> String { String(format: "0x%08X", UInt32(bitPattern: code)) }

private let ioReturnNotPermitted = IOReturn(bitPattern: 0xE00002E2)
private let ioReturnExclusiveAccess = IOReturn(bitPattern: 0xE00002C5)

/// What macOS says about Input Monitoring for this process.
public enum InputMonitoring: String, Sendable {
    case granted, denied, unknown

    public static var current: InputMonitoring {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: .granted
        case kIOHIDAccessTypeDenied: .denied
        default: .unknown
        }
    }

    /// Shows the system prompt if the user has not decided yet. Returns true if granted.
    @discardableResult
    public static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}

/// An open connection to one pad. Lives on the main run loop; every callback lands there.
@MainActor
public final class Pad {
    public let info: PadInfo

    /// A notification from the pad: key, dial, joystick or unknown.
    public var onEvent: ((PadEvent) -> Void)?
    /// A line from the firmware's debug channel.
    public var onDebugLine: ((String) -> Void)?
    /// Text on the RPC channel that never became a message.
    public var onUnreadable: ((String) -> Void)?
    /// An answer to a request another app sent: its id, and its method when the pad names it.
    public var onOtherReply: ((_ id: String, _ method: String?) -> Void)?
    /// A report outside the vendor channel: the pad sending keys, clicks or pointer moves as
    /// a keyboard or mouse would, which it does on layers other than the first.
    public var onOtherInput: (() -> Void)?
    /// Every raw report, in (`true`) and out (`false`). For `--trace`.
    public var onTrace: (([UInt8], _ incoming: Bool) -> Void)?
    /// The pad went away (unplugged, Bluetooth dropped), or the helper did.
    public var onDisconnect: (() -> Void)?

    public private(set) var isConnected = true
    /// Whether no other app hears the pad now. Only the helper can do that (`hold(_:)`).
    public private(set) var isHeld = false
    /// Why the helper was not used for this connection, when it is installed but was not.
    public private(set) var helperNote: String?

    private let link: PadLink
    private var lines = LineAssembler()
    private var messages = MessageAssembler()
    private var responses: [String: (result: JSONValue?, error: RPCError?)] = [:]
    /// Requests in flight, by id.
    private var pending: [String: Method] = [:]
    private var nextID = Int.random(in: 1 ... 998)
    private var lastSend = Date.distantPast

    /// Minimum gap between requests; the vendor app waits the same.
    public static let requestGap: TimeInterval = 0.05
    /// The gap this pad keeps. A made-up pad in a test keeps none, so a test does not hold the
    /// main thread 50 ms for every request.
    var gap = Pad.requestGap

    // MARK: Finding

    /// Every attached pad that carries the vendor interface, USB first.
    public static func find() -> [PadInfo] {
        PadDevices.all().map(\.info)
    }

    // MARK: Opening

    /// Opens the first pad found (USB preferred). Through the helper when it is installed and
    /// will serve this program (`helper` false skips it); then the pad can be held, so other
    /// apps hear nothing. Otherwise directly and shared: ChatGPT and other apps keep it open
    /// too, every app hears every key, and `PadSharing` decides who acts. macOS turns an
    /// exclusive open from anything but root away as not privileged (0xE00002C1, 2026-11-21).
    public static func open(helper: Bool = true) throws(PadError) -> Pad {
        var note: String?
        if helper {
            switch throughHelper() {
            case let .connected(pad): return pad
            case let .refused(reason): note = reason
            case .absent: break
            }
        }
        guard let (device, info) = PadDevices.all().first else { throw .notFound }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        switch result {
        case kIOReturnSuccess: break
        case ioReturnNotPermitted: throw .inputMonitoringDenied
        case ioReturnExclusiveAccess: throw .busy
        default: throw .openFailed(result)
        }
        return Pad(link: HIDLink(device: device, info: info), info: info, note: note)
    }

    public enum HelperAttempt {
        /// MicroBridge Helper is not installed, or not running.
        case absent
        /// It will not serve this program, and why.
        case refused(String)
        case connected(Pad)
    }

    /// Opens the pad through MicroBridge Helper only.
    public static func throughHelper() -> HelperAttempt {
        switch HelperLink.connect() {
        case let .connected(link, info): .connected(Pad(link: link, info: info, note: nil))
        case let .refused(reason): .refused(reason)
        case .absent: .absent
        }
    }

    /// Tests pass a link of their own.
    init(link: PadLink, info: PadInfo, note: String?) {
        self.link = link
        self.info = info
        helperNote = note
        link.onReport = { [unowned self] bytes in received(bytes) }
        link.onGone = { [unowned self] in removed() }
        link.start()
    }

    /// Stops callbacks and closes the device. Call before dropping the last reference.
    public func close() {
        link.close()
        isConnected = false
        isHeld = false
    }

    /// Whether this connection can hold the pad: it goes through the helper.
    public var canHold: Bool { link.canHold }

    /// Takes the pad for this program alone (`true`), or shares it again. Through the helper
    /// only; a direct connection throws `.helper`. If macOS turns the hold away, the pad stays
    /// open, shared, and this throws `.holdFailed`.
    public func hold(_ on: Bool) throws(PadError) {
        guard isConnected else { throw .disconnected }
        let (held, result) = try link.hold(on)
        isHeld = held
        if result != kIOReturnSuccess { throw .holdFailed(result) }
    }

    // MARK: Talking

    /// Sends one request and waits for its answer, spinning the main run loop meanwhile.
    @discardableResult
    public func call(_ method: Method, params: JSONValue = .null, timeout: TimeInterval = 10) throws(PadError) -> JSONValue? {
        guard isConnected else { throw .disconnected }
        let wait = lastSend.addingTimeInterval(gap).timeIntervalSinceNow
        if wait > 0 { Pad.spin(for: wait) }

        nextID = nextID % 998 + 1
        let id = String(nextID)
        pending[id] = method
        defer { pending[id] = nil }
        let text = RPC.request(method, params: params, id: nextID)
        if let onTrace { for report in Framing.reports(for: Array(text.utf8)) { onTrace(report, false) } }
        let result = try link.write(text)
        guard result == kIOReturnSuccess else { throw PadError.writing(result) }
        lastSend = Date()

        let deadline = Date().addingTimeInterval(timeout)
        while responses[id] == nil {
            guard isConnected else { throw .disconnected }
            guard Date() < deadline else { throw .timeout(method) }
            link.pump()
            if responses[id] != nil { break }
            Pad.spin(for: 0.01)
        }
        let answer = responses.removeValue(forKey: id)!
        if let error = answer.error { throw .rpc(method, error) }
        return answer.result
    }

    public func status(timeout: TimeInterval = 10) throws(PadError) -> DeviceStatus {
        DeviceStatus(try call(.status, timeout: timeout) ?? .null)
    }

    public func setSlots(_ slots: [SlotLight], timeout: TimeInterval = 10) throws(PadError) {
        try call(.threadsLighting, params: .array(slots.map(\.json)), timeout: timeout)
    }

    public func setZones(ambient: ZoneLight, keys: ZoneLight) throws(PadError) {
        try call(.lightingConfig, params: .object([("ambient", ambient.json), ("keys", keys.json)]))
    }

    /// The six Agent Keys dark. The two zones stay as they are.
    public func slotsOff(timeout: TimeInterval = 10) throws(PadError) {
        try setSlots((0 ..< 6).map { AgentStatus.off.light(slot: $0) }, timeout: timeout)
    }

    /// Everything dark: both zones and all six Agent Keys.
    public func allOff() throws(PadError) {
        try setZones(ambient: .off, keys: .off)
        try slotsOff()
    }

    /// Runs the main run loop so callbacks fire.
    public static func spin(for seconds: TimeInterval) {
        _ = CFRunLoopRunInMode(.defaultMode, seconds, false)
    }

    // MARK: Callbacks

    private func received(_ report: [UInt8]) {
        onTrace?(report, true)
        guard report.first == Framing.reportID else {
            onOtherInput?()
            return
        }
        for line in lines.feed(report) {
            if line.channel == Framing.Channel.rpc.rawValue {
                let message = messages.feed(line: line.text)
                for text in messages.takeDropped() { onUnreadable?(text) }
                guard let message else { continue }
                switch message {
                case let .response(id, method, result, error):
                    // Only keep answers to what this process asked. Other apps (ChatGPT, Work
                    // Louder Input) share the stream and pick ids at random too.
                    guard let asked = pending[id], method == nil || method == asked.rawValue else {
                        onOtherReply?(id, method)
                        continue
                    }
                    responses[id] = (result, error)
                case let .notification(method, params):
                    onEvent?(PadEvent(method: method, params: params))
                }
            } else {
                onDebugLine?(line.text)
            }
        }
    }

    private func removed() {
        guard isConnected else { return }
        isConnected = false
        isHeld = false
        onDisconnect?()
    }
}

// MARK: Links

/// How a `Pad` reaches the device: directly through IOKit, or through the root helper.
@MainActor
protocol PadLink: AnyObject {
    /// One input report, report ID first.
    var onReport: (([UInt8]) -> Void)? { get set }
    var onGone: (() -> Void)? { get set }
    var canHold: Bool { get }
    /// Starts callbacks on the main run loop.
    func start()
    /// Writes one request. Returns the IOReturn of the write.
    func write(_ request: String) throws(PadError) -> IOReturn
    /// Returns whether the pad is held now, and the IOReturn of the change.
    func hold(_ on: Bool) throws(PadError) -> (Bool, IOReturn)
    /// Hands over what has arrived but not been handed over yet. A wait inside a callback
    /// calls it, since the link's own callback cannot fire again until that one returns.
    func pump()
    func close()
}

/// The pad opened directly, shared with every other app that has it open.
@MainActor
final class HIDLink: PadLink {
    var onReport: (([UInt8]) -> Void)?
    var onGone: (() -> Void)?
    var canHold: Bool { false }
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private var open = true
    private var closed = false

    init(device: IOHIDDevice, info: PadInfo) {
        self.device = device
        bufferSize = max(info.maxInputReport, Framing.reportSize)
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let link = Unmanaged<HIDLink>.fromOpaque(context).takeUnretainedValue()
            let bytes = Framing.normalized(Array(UnsafeBufferPointer(start: report, count: length)), reportID: reportID)
            MainActor.assumeIsolated { link.onReport?(bytes) }
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            let link = Unmanaged<HIDLink>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                link.open = false
                link.onGone?()
            }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func write(_ request: String) throws(PadError) -> IOReturn {
        for report in Framing.reports(for: Array(request.utf8)) {
            let result = report.withUnsafeBufferPointer { bytes in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Framing.reportID), bytes.baseAddress!, bytes.count)
            }
            if result != kIOReturnSuccess { return result }
        }
        return kIOReturnSuccess
    }

    func hold(_: Bool) throws(PadError) -> (Bool, IOReturn) {
        throw .helper("the pad is open directly, not through the helper, so it cannot be held")
    }

    func pump() {}

    func close() {
        guard !closed else { return }
        closed = true
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if open { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        open = false
        buffer.deallocate()
    }
}

/// The pad through MicroBridge's root helper (`micro-helper`), which can hold it so that no
/// other app hears it. The helper writes only the methods in `Method`.
@MainActor
final class HelperLink: PadLink {
    var onReport: (([UInt8]) -> Void)?
    var onGone: (() -> Void)?
    var canHold: Bool { true }
    private let fd: Int32
    private var reader: HelperWire.FrameReader
    /// Frames read but not handed over yet, oldest first.
    private var inbox: [HelperWire.Frame]
    /// The helper's answers to `send` and `hold`, oldest first.
    private var answers: [HelperWire.Frame] = []
    private var descriptor: CFFileDescriptor?
    private var source: CFRunLoopSource?
    private var open = true

    enum Connection {
        /// No helper is listening.
        case absent
        /// The helper will not serve this program, and why.
        case refused(String)
        case connected(HelperLink, PadInfo)
    }

    /// How long the helper may take to answer.
    static let answerTimeout: TimeInterval = 2

    static func connect(path: String = HelperWire.socketPath) -> Connection {
        guard FileManager.default.fileExists(atPath: path) else { return .absent }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .absent }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            return .absent
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            // Not running, or this account may not use its socket.
            Darwin.close(fd)
            return .absent
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // The helper speaks first: the pad it opened, or why it will not serve this program.
        var reader = HelperWire.FrameReader()
        var frames: [HelperWire.Frame] = []
        let deadline = Date().addingTimeInterval(answerTimeout)
        while frames.isEmpty {
            let left = Int32(max(0, deadline.timeIntervalSinceNow) * 1000)
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            var chunk = [UInt8](repeating: 0, count: 4096)
            guard left > 0, poll(&poller, 1, left) == 1 else {
                Darwin.close(fd)
                return .refused("the helper did not answer")
            }
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else {
                Darwin.close(fd)
                return .refused("the helper hung up")
            }
            frames = reader.feed(Array(chunk[0 ..< count]))
            if reader.broken { break }
        }
        switch frames.first {
        case let .info(info):
            return .connected(HelperLink(fd: fd, reader: reader, inbox: Array(frames.dropFirst())), info)
        case let .refused(reason):
            Darwin.close(fd)
            return .refused("the helper refused: \(reason)")
        default:
            Darwin.close(fd)
            return .refused("the helper sent something unexpected")
        }
    }

    private init(fd: Int32, reader: HelperWire.FrameReader, inbox: [HelperWire.Frame]) {
        self.fd = fd
        self.reader = reader
        self.inbox = inbox
    }

    func start() {
        var context = CFFileDescriptorContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        descriptor = CFFileDescriptorCreate(nil, fd, true, { descriptor, _, info in
            guard let info else { return }
            let link = Unmanaged<HelperLink>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { link.readable() }
        }, &context)
        guard let descriptor else {
            gone()
            return
        }
        CFFileDescriptorEnableCallBacks(descriptor, kCFFileDescriptorReadCallBack)
        source = CFFileDescriptorCreateRunLoopSource(nil, descriptor, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        // Reports that came with the helper's first frame.
        DispatchQueue.main.async { MainActor.assumeIsolated { self.pump() } }
    }

    private func readable() {
        guard open else { return }
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let count = read(fd, &chunk, chunk.count)
        guard count > 0 else {
            gone()
            return
        }
        for frame in reader.feed(Array(chunk[0 ..< count])) {
            switch frame {
            case .sent, .holding: answers.append(frame)
            default: inbox.append(frame)
            }
        }
        guard !reader.broken else {
            gone()
            return
        }
        if let descriptor { CFFileDescriptorEnableCallBacks(descriptor, kCFFileDescriptorReadCallBack) }
        pump()
    }

    func pump() {
        while open, !inbox.isEmpty {
            switch inbox.removeFirst() {
            case let .report(bytes): onReport?(bytes)
            case .gone: gone()
            default: break
            }
        }
    }

    /// Sends one frame and waits for the helper's answer to it: the first answer of the same
    /// kind, since the helper answers in order and a wait may start inside another one.
    private func ask(_ frame: HelperWire.Frame) throws(PadError) -> HelperWire.Frame {
        guard open else { throw .disconnected }
        let bytes = frame.encoded
        let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == bytes.count else {
            gone()
            throw .disconnected
        }
        let sameKind: (HelperWire.Frame) -> Bool = { answer in
            switch (frame, answer) {
            case (.send, .sent), (.hold, .holding): true
            default: false
            }
        }
        let deadline = Date().addingTimeInterval(Self.answerTimeout)
        while true {
            if let index = answers.firstIndex(where: sameKind) { return answers.remove(at: index) }
            guard open else { throw .disconnected }
            guard Date() < deadline else { throw .helper("the helper did not answer") }
            Pad.spin(for: 0.005)
        }
    }

    func write(_ request: String) throws(PadError) -> IOReturn {
        guard case let .sent(code) = try ask(.send(request)) else { throw .helper("the helper answered out of turn") }
        if code == HelperWire.refusedRequest { throw .helper("the helper will not send that request") }
        return code
    }

    func hold(_ on: Bool) throws(PadError) -> (Bool, IOReturn) {
        guard case let .holding(held, code) = try ask(.hold(on)) else { throw .helper("the helper answered out of turn") }
        return (held, code)
    }

    private func gone() {
        guard open else { return }
        close()
        onGone?()
    }

    func close() {
        guard open else { return }
        open = false
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        // Closes the socket too; the helper then shares the pad again at once.
        if let descriptor { CFFileDescriptorInvalidate(descriptor) } else { Darwin.close(fd) }
        source = nil
        descriptor = nil
        inbox.removeAll()
        answers.removeAll()
    }
}
