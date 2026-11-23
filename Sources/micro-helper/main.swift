// micro-helper: MicroBridge's optional helper. It runs as root, because macOS lets only root
// take a keyboard-class device for itself, and the Codex Micro's key channel is part of its
// keyboard. While MicroBridge asks it to, the helper holds the pad so that no other app (such
// as ChatGPT) hears its keys or changes its lights. It does nothing else:
//
// - It opens only the Codex Micro (PadDevices), and only while MicroBridge is connected.
// - It writes only the five methods in `Method`, rebuilt by `HelperWire.checkedRequest`.
// - It serves one account (`--user`), and only a program signed as MicroBridge with the same
//   certificate as the helper itself.
// - When MicroBridge hangs up or quits, it lets go of the pad at once.
// - No network, no files besides its socket, no settings. Its log says who connected and when
//   it held or shared the pad; never what was pressed.

import CryptoKit
import Darwin
import Foundation
import IOKit
import IOKit.hid
import PadWire
import Security

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ text: String) {
    print(ISO8601DateFormatter().string(from: Date()), text)
}

// MARK: Arguments

var allowedUser: uid_t?
var socketPath = HelperWire.socketPath
var arguments = CommandLine.arguments.dropFirst()
while let flag = arguments.popFirst() {
    switch flag {
    case "--user": allowedUser = arguments.popFirst().flatMap { uid_t($0) }
    case "--socket": socketPath = arguments.popFirst() ?? socketPath
    default:
        log("unknown argument \(flag)")
        exit(2)
    }
}
guard let allowedUser else {
    log("usage: micro-helper --user <uid> [--socket <path>]")
    exit(2)
}

// MARK: Who may connect

/// MicroBridge, signed with the same certificate as this helper. Nil when the helper itself is
/// not signed with a certificate: then it cannot tell MicroBridge from anything else, and
/// serves nobody.
let clientRequirement: SecRequirement? = {
    var me: SecCode?
    var mine: SecStaticCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
          SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
          SecCodeCopySigningInformation(mine, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
          let leaf = certificates.first
    else { return nil }
    let hash = Insecure.SHA1.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02X", $0) }.joined()
    var requirement: SecRequirement?
    let text = #"identifier "local.micro-bridge" and certificate leaf = H"\#(hash)""#
    guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
    return requirement
}()

/// Why the program on the other end of `fd` may not use the helper, or nil when it may.
@MainActor
func refusal(_ fd: Int32) -> String? {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid == allowedUser else { return "another account" }
    guard let clientRequirement else { return "the helper is not signed with a certificate, so it cannot check who connects" }
    var token = audit_token_t()
    var length = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(fd, 0 /* SOL_LOCAL */, 0x006 /* LOCAL_PEERTOKEN */, &token, &length) == 0 else {
        return "no audit token"
    }
    let tokenData = withUnsafeBytes(of: &token) { Data($0) }
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code) == errSecSuccess,
          let code
    else { return "cannot read its signature" }
    guard SecCodeCheckValidity(code, [], clientRequirement) == errSecSuccess else { return "not signed as MicroBridge" }
    return nil
}

// MARK: The pad

/// The pad, open for one connection.
@MainActor
final class HeldPad {
    let device: IOHIDDevice
    let info: PadInfo
    private(set) var held = false
    private var open = false
    /// Read only by the deinit once nothing else holds the pad.
    nonisolated(unsafe) private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
    var onReport: (([UInt8]) -> Void)?
    var onGone: (() -> Void)?

    init(device: IOHIDDevice, info: PadInfo) {
        self.device = device
        self.info = info
    }

    deinit { buffer.deallocate() }

    /// Opens the pad, shared or held. Returns the IOReturn.
    func start(hold: Bool) -> IOReturn {
        let result = IOHIDDeviceOpen(device, IOOptionBits(hold ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return result }
        open = true
        held = hold
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 1024, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let pad = Unmanaged<HeldPad>.fromOpaque(context).takeUnretainedValue()
            let bytes = Framing.normalized(Array(UnsafeBufferPointer(start: report, count: length)), reportID: reportID)
            MainActor.assumeIsolated { pad.onReport?(bytes) }
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            let pad = Unmanaged<HeldPad>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { pad.onGone?() }
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        return result
    }

    func stop() {
        guard open else { return }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 1024, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        open = false
        held = false
    }

    /// Switches between held and shared. If holding fails, the pad stays open, shared.
    func setHeld(_ hold: Bool) -> IOReturn {
        guard hold != held else { return kIOReturnSuccess }
        stop()
        let result = start(hold: hold)
        if result != kIOReturnSuccess, hold { _ = start(hold: false) }
        return result
    }

    func write(_ request: String) -> IOReturn {
        for report in Framing.reports(for: Array(request.utf8)) {
            let result = report.withUnsafeBufferPointer { bytes in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Framing.reportID), bytes.baseAddress!, bytes.count)
            }
            if result != kIOReturnSuccess { return result }
        }
        return kIOReturnSuccess
    }
}

// MARK: One connection

@MainActor
final class Connection {
    let fd: Int32
    private var reader = HelperWire.FrameReader()
    private var source: DispatchSourceRead?
    private var pad: HeldPad?
    var onClose: (() -> Void)?

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        // A MicroBridge that stops reading must not stall the helper.
        var wait = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
    }

    func start() {
        guard let (device, info) = PadDevices.all().first else {
            refuse("no pad found")
            return
        }
        let pad = HeldPad(device: device, info: info)
        let result = pad.start(hold: false)
        guard result == kIOReturnSuccess else {
            guard result == IOReturn(bitPattern: 0xE000_02E2) else {
                refuse(String(format: "could not open the pad (IOReturn 0x%08X)", UInt32(bitPattern: result)))
                return
            }
            refuse("Input Monitoring is off for MicroBridge Helper: switch it on under System Settings > Privacy & Security > Input Monitoring")
            // macOS keeps saying no to a process that started before the switch went on
            // (seen 2026-11-21). launchd starts the helper again, and the new one is let in.
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted || Date() > startedAt + 120 {
                log("starting again, so that macOS reads Input Monitoring afresh")
                exit(0)
            }
            return
        }
        lastRefusal = nil
        log("MicroBridge connected")
        pad.onReport = { [weak self] report in self?.send(.report(report)) }
        pad.onGone = { [weak self] in
            log("the pad went away")
            self?.send(.gone)
            self?.close()
        }
        self.pad = pad
        send(.info(info))
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.readable() }
        source.resume()
        self.source = source
    }

    private func readable() {
        var bytes = [UInt8](repeating: 0, count: 8192)
        let count = read(fd, &bytes, bytes.count)
        guard count > 0 else {
            close()
            return
        }
        for frame in reader.feed(Array(bytes[0 ..< count])) { handle(frame) }
        if reader.broken {
            log("MicroBridge sent something that is not a helper frame: hanging up")
            close()
        }
    }

    private func handle(_ frame: HelperWire.Frame) {
        guard let pad else { return }
        switch frame {
        case let .send(text):
            guard let request = HelperWire.checkedRequest(text) else {
                log("refused a request outside the five allowed methods")
                send(.sent(HelperWire.refusedRequest))
                return
            }
            send(.sent(pad.write(request)))
        case let .hold(on):
            let result = pad.setHeld(on)
            if result == kIOReturnSuccess {
                log(on ? "holding the pad for MicroBridge alone" : "sharing the pad")
            } else {
                log(String(format: "could not %@ the pad (IOReturn 0x%08X)", on ? "hold" : "share", UInt32(bitPattern: result)))
            }
            send(.holding(pad.held, result))
        default:
            log("MicroBridge sent a frame only the helper sends: hanging up")
            close()
        }
    }

    func send(_ frame: HelperWire.Frame) {
        let bytes = frame.encoded
        let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        if written != bytes.count, source != nil { close() }
    }

    private func refuse(_ reason: String) {
        logRefusal(reason)
        send(.refused(reason))
        Darwin.close(fd)
        onClose?()
    }

    func close() {
        guard let source else { return }
        self.source = nil
        source.cancel()
        if pad?.held == true { log("MicroBridge hung up: sharing the pad again") }
        pad?.stop()
        pad = nil
        Darwin.close(fd)
        onClose?()
    }
}

/// MicroBridge asks again every half minute while it is refused; one line per new reason.
var lastRefusal: String?
let startedAt = Date()
@MainActor func logRefusal(_ reason: String) {
    guard reason != lastRefusal else { return }
    lastRefusal = reason
    log("refused a connection: \(reason)")
}

// MARK: The socket

unlink(socketPath)
let listener = socket(AF_UNIX, SOCK_STREAM, 0)
guard listener >= 0 else {
    log("cannot make a socket: \(String(cString: strerror(errno)))")
    exit(1)
}
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
    log("socket path too long")
    exit(1)
}
withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.copyBytes(from: pathBytes)
    raw[pathBytes.count] = 0
}
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
// Only the served account may connect (root always can).
guard bound == 0, chown(socketPath, allowedUser, gid_t(bitPattern: -1)) == 0, chmod(socketPath, 0o600) == 0,
      listen(listener, 4) == 0
else {
    log("cannot listen on \(socketPath): \(String(cString: strerror(errno)))")
    exit(1)
}

var current: Connection?
let accepting = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
accepting.setEventHandler {
    let fd = accept(listener, nil, nil)
    guard fd >= 0 else { return }
    let connection = Connection(fd: fd)
    if current != nil {
        connection.send(.refused("another connection is using the helper"))
        close(fd)
        return
    }
    if let reason = refusal(fd) {
        logRefusal(reason)
        connection.send(.refused(reason))
        close(fd)
        return
    }
    current = connection
    connection.onClose = { current = nil }
    connection.start()
}
accepting.resume()

if getuid() != 0 { log("not running as root: macOS will refuse to hold the pad") }
if clientRequirement == nil { log("this helper is not signed with a certificate: it will serve nobody") }
// Puts the helper in the Input Monitoring list, so it can be switched on there.
if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
    log("Input Monitoring is not on for MicroBridge Helper yet: switch it on in System Settings")
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}
log("micro-helper started for uid \(allowedUser), listening on \(socketPath)")
CFRunLoopRun()
