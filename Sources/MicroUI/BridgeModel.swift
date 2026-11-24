import AppKit
import Foundation
import MicroKit
import ServiceManagement

/// One session as the bridge reports it.
struct SessionRow: Identifiable, Equatable, Sendable {
    let id: String
    var slot: Int?
    var status: AgentStatus
    var cwd: String?
    var host: String?
    var ended = false
    /// It keeps its key until it is unpinned or forgotten.
    var pinned = false

    /// The folder the session works in, which is the only name the bridge knows it by.
    var name: String {
        guard let cwd, !cwd.isEmpty else { return "Claude session" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// One key of Orca's layer as the bridge reports it.
struct OrcaKeyRow: Identifiable, Equatable, Sendable {
    /// 0 to 5.
    var slot: Int
    /// Orca's session ID of the chat on the key.
    var chat: String
    var status: AgentStatus
    /// Its tab was closed in Orca: the key is dim until it is freed.
    var closed = false
    /// What Orca called the chat when the bridge last heard.
    var title: String?

    var id: Int { slot }
}

/// Orca's layer as the bridge reports it: which layer it is, and the chats on its six keys.
struct OrcaSnapshot: Equatable, Sendable {
    var layer: Int
    var keys: [OrcaKeyRow] = []

    init(layer: Int, keys: [OrcaKeyRow] = []) {
        self.layer = layer
        self.keys = keys
    }

    /// Nil when the bridge has no layer for Orca.
    init?(reply: JSONValue?) {
        guard let reply, let layer = reply["layer"]?.int else { return nil }
        self.layer = layer
        if case let .array(items)? = reply["keys"] {
            keys = items.compactMap { item in
                guard let slot = item["slot"]?.int, (0 ..< BridgeState.slotCount).contains(slot),
                      let chat = item["session"]?.string,
                      let status = AgentStatus(rawValue: item["status"]?.string ?? "") else { return nil }
                return OrcaKeyRow(slot: slot, chat: chat, status: status, closed: item["closed"]?.bool == true,
                                  title: item["title"]?.string)
            }
        }
    }

    func key(_ slot: Int) -> OrcaKeyRow? {
        keys.first { $0.slot == slot }
    }

    /// What the six keys show.
    var slots: [AgentStatus] {
        (0 ..< BridgeState.slotCount).map { key($0)?.status ?? .off }
    }
}

/// What the bridge answered to "state". `running` is false when it did not answer.
struct BridgeSnapshot: Equatable, Sendable {
    var running = false
    var connected = false
    var slots = [AgentStatus](repeating: .off, count: 6)
    var sessions: [SessionRow] = []
    var pulsing: Set<Int> = []
    var transport: String?
    var firmware: String?
    var battery: Int?
    var charging: Bool?
    var layer: Int?
    var inputMonitoring: String?
    var accessibility: Bool?
    /// Orca's layer and its keys, when the config gives Orca a layer.
    var orca: OrcaSnapshot?

    init() {}

    init(reply: JSONValue) {
        running = reply["ok"]?.bool == true
        connected = reply["connected"]?.bool == true
        if case let .array(items)? = reply["slots"], items.count == slots.count {
            slots = items.map { AgentStatus(rawValue: $0.string ?? "") ?? .off }
        }
        if case let .array(items)? = reply["sessions"] {
            sessions = items.compactMap { item in
                guard let id = item["session"]?.string,
                      let status = AgentStatus(rawValue: item["status"]?.string ?? "") else { return nil }
                return SessionRow(id: id, slot: item["slot"]?.int, status: status, cwd: item["cwd"]?.string,
                                  host: item["host"]?.string, ended: item["ended"]?.bool == true,
                                  pinned: item["pinned"]?.bool == true)
            }
        }
        if case let .array(items)? = reply["pulsing"] { pulsing = Set(items.compactMap(\.int)) }
        transport = reply["transport"]?.string
        firmware = reply["firmware"]?.string
        battery = reply["battery"]?.int
        charging = reply["charging"]?.bool
        layer = reply["layer"]?.int
        inputMonitoring = reply["inputMonitoring"]?.string
        accessibility = reply["accessibility"]?.bool
        orca = OrcaSnapshot(reply: reply["orca"])
    }

    /// Made-up sessions for screenshots and for trying the window without a bridge. They are
    /// kept by the bridge's own rules, so Pin, Unpin and Forget act as they do for real.
    static let demoSessions: BridgeState = {
        var state = BridgeState()
        let folders = ["storefront", "billing-api", "ios-app", "docs-site", "data-pipeline", "design-system"]
        let statuses: [AgentStatus] = [.working, .needsYou, .done, .idle, .failed, .working]
        for (slot, status) in statuses.enumerated() {
            state.apply(.report(session: "demo-\(slot)", status: status, pid: nil, cwd: "/code/" + folders[slot],
                                host: SessionHost("claude:local_demo\(slot)")))
        }
        // One pinned session that has ended: it keeps key 4, and the seventh session waits.
        state.pin("demo-3")
        state.apply(.end(session: "demo-3"))
        state.apply(.report(session: "demo-6", status: .working, pid: nil, cwd: "/code/infra"))
        state.onScreen = [.claudeDesktop("local_demo0")]
        return state
    }()

    /// A made-up pad on USB that shows those sessions.
    static func demo(_ sessions: BridgeState, orca: (layer: Int, keys: OrcaKeys)? = nil) -> BridgeSnapshot {
        var demo = JSONValue.parse(Reply.state(sessions, pad: nil, shown: sessions.onScreen, orca: orca))
            .map(BridgeSnapshot.init(reply:)) ?? BridgeSnapshot()
        demo.connected = true
        demo.transport = "USB"
        demo.firmware = "v0.6.1"
        demo.battery = 82
        demo.charging = true
        demo.layer = LayerWatch.ours
        demo.inputMonitoring = InputMonitoring.granted.rawValue
        demo.accessibility = true
        return demo
    }
}

/// The files the app reads and writes.
struct BridgeFiles: Sendable {
    var config = BridgePaths.config
    var socket = BridgePaths.socket
    var log = NSHomeDirectory() + "/Library/Logs/micro-bridge.log"
    var claudeSettings = NSHomeDirectory() + "/.claude/settings.json"
    /// The login item `scripts/install` writes. The app's own login item must not run beside it.
    var launchAgent = NSHomeDirectory() + "/Library/LaunchAgents/local.micro-bridge.plist"
}

/// How the bridge starts when you log in (D-025): the LaunchAgent `scripts/install` writes, or
/// the app's own entry under Login Items. Never both, or two bridges would start.
enum LoginStart: Equatable, Sendable {
    /// `scripts/install` starts it.
    case scripts
    /// The app's login item is on.
    case on
    /// Registered, and waiting for the person to allow it in System Settings.
    case needsApproval
    case off
    /// Not run from MicroBridge.app, which carries the login item.
    case unavailable
}

/// One thing a person can do to get the pad working, most important first.
struct NextStep {
    var text: String
    var button: String?
    var run: (@MainActor () -> Void)?
}

/// What a key is set to in the file.
/// What turning the dial moves through.
enum DialTurn: Hashable {
    case answers, sessions
    /// Anything else the file says.
    case own

    /// The commands for a clockwise and an anticlockwise turn. Anticlockwise goes down the list,
    /// as with the stock answers.
    var commands: (cw: String, ccw: String)? {
        switch self {
        case .answers: ("cmd:PREV", "cmd:NEXT")
        case .sessions: ("cmd:BACK", "cmd:FORWARD")
        case .own: nil
        }
    }
}

enum Keycap: Equatable {
    /// The whole key is one command: each of the command's triggers is the key's.
    case command(String)
    case nothing
    /// The key has its own actions: a single action, a list, or an object of triggers.
    case custom(String)
}

/// Everything the window shows: the bridge's live state and the config file.
@MainActor
final class BridgeModel: ObservableObject {
    @Published private(set) var bridge = BridgeSnapshot()
    @Published private(set) var config = Config.builtIn
    /// What is wrong with the config file, in the bridge's own words. Empty when it is fine.
    @Published private(set) var problems: [String] = []
    /// How many Claude Code events call the bridge's hook. Nil when the settings cannot be read.
    @Published private(set) var hookEvents: Int?
    @Published private(set) var log: [String] = []
    @Published private(set) var loginStart = LoginStart.unavailable
    /// Why the last change was not made.
    @Published var notice: String?
    /// The Claude chats open in Orca, as the bridge lists them. They name the chats on Orca's
    /// keys, and the others can be put on a key.
    @Published private(set) var orcaChats: [OrcaChat] = []

    let files: BridgeFiles
    let isDemo: Bool
    static let hookEventsWanted = ClaudeSettings.events.count

    /// What adds the hook, run in Terminal: this program's own `hooks install`. The window copies
    /// it and never writes Claude Code's settings itself (D-024).
    var hookCommand: String {
        ClaudeSettings.installCommand(executable: Bundle.main.executablePath ?? "/Applications/MicroBridge.app/Contents/MacOS/micro")
    }

    func copyHookCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hookCommand, forType: .string)
        notice = "Copied. Paste it in Terminal and press Return."
    }

    let defaults = ConfigFile(text: Config.defaultFileText)
    private(set) var file: ConfigFile?
    private var fileStamp: Date?
    private var loaded = false
    private var timer: Timer?
    private var fetching = false
    private var unsaved: String?
    private var saving: Task<Void, Never>?
    private var demoSessions = BridgeSnapshot.demoSessions
    private var demoOrca: OrcaKeys?
    private var demoLayer = LayerWatch.ours
    private var askedOrca = Date.distantPast
    private var askingOrca = false

    init(files: BridgeFiles = BridgeFiles(), demo: Bool = false) {
        self.files = files
        isDemo = demo
        file = defaults
        if demo {
            bridge = demoBridge()
            hookEvents = Self.hookEventsWanted
            loginStart = .on
            log = [
                "pad connected: Codex Micro over USB",
                "session storefront gets key 1",
                "key 2 is amber: a permission prompt is waiting",
                "AG.press key 3: ack, jump",
            ]
        }
    }

    /// Reads the config and asks the bridge for its state once a second.
    func start() {
        guard !isDemo, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isDemo else { return }
        loadConfig()
        guard !fetching else { return }
        fetching = true
        let files = files
        // The reading happens off the main thread and hands back plain values; only this task,
        // on the main actor, touches the model. Older compilers refuse to send `self` across.
        Task { [weak self] in
            let (snapshot, hooks, tail, login) = await Task.detached(priority: .utility) {
                (Self.fetch(socket: files.socket), Self.hookEvents(settings: files.claudeSettings),
                 Self.tail(of: files.log, lines: 14), Self.loginStart(launchAgent: files.launchAgent))
            }.value
            guard let self else { return }
            self.fetching = false
            if self.bridge != snapshot { self.bridge = snapshot }
            if snapshot.orca != nil { self.refreshOrcaChats() } else if !self.orcaChats.isEmpty { self.orcaChats = [] }
            if self.hookEvents != hooks { self.hookEvents = hooks }
            if self.log != tail { self.log = tail }
            if self.loginStart != login { self.loginStart = login }
        }
    }

    // MARK: The bridge

    private nonisolated static func fetch(socket: String) -> BridgeSnapshot {
        var reply: JSONValue?
        try? SocketClient.send(#"{"op":"state"}"#, to: socket, timeout: 1) { line in
            reply = JSONValue.parse(line)
            return false
        }
        return reply.map(BridgeSnapshot.init(reply:)) ?? BridgeSnapshot()
    }

    /// The property list inside MicroBridge.app that the login item starts (scripts/bundle).
    nonisolated static let agentPlist = "local.micro-bridge.plist"

    private nonisolated static func loginStart(launchAgent: String) -> LoginStart {
        if FileManager.default.fileExists(atPath: launchAgent) { return .scripts }
        switch SMAppService.agent(plistName: agentPlist).status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered: return .off
        default: return .unavailable
        }
    }

    /// Starts the bridge now and at every login, through the app's own login item.
    func startAtLogin() {
        guard !isDemo, loginStart != .scripts else { return }
        do {
            try SMAppService.agent(plistName: Self.agentPlist).register()
        } catch {
            notice = "Could not start the bridge at login: \(error.localizedDescription)"
        }
        loginStart = Self.loginStart(launchAgent: files.launchAgent)
        if loginStart == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Stops the bridge and takes it out of Login Items.
    func stopAtLogin() {
        guard !isDemo, loginStart != .scripts else { return }
        do {
            try SMAppService.agent(plistName: Self.agentPlist).unregister()
            notice = "The bridge has stopped and will not start when you log in."
        } catch {
            notice = "Could not take the bridge out of Login Items: \(error.localizedDescription)"
        }
        loginStart = Self.loginStart(launchAgent: files.launchAgent)
    }

    func openLoginItems() {
        guard !isDemo else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Counts the Claude Code events that reach the bridge, through the settings or the plugin.
    private nonisolated static func hookEvents(settings path: String) -> Int? {
        ClaudeSettings.reportingEvents(path: path)
    }

    private nonisolated static func tail(of path: String, lines: Int) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 8192 ? size - 8192 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        var found = text.split(separator: "\n").map(String.init)
        if size > 8192, !found.isEmpty { found.removeFirst() } // the first line is cut in half
        return Array(found.suffix(lines))
    }

    /// Sends the bridge a command. When the bridge refuses, `notice` says why.
    private func send(_ pairs: [(String, JSONValue)], timeout: TimeInterval = 1) {
        let line = JSONValue.object(pairs).serialized
        if isDemo {
            if let command = try? Command.parse(line) {
                switch command {
                case let .orcaTake(slot, chat):
                    if let found = orcaChatsOffKeys.first(where: { chat == nil || $0.id == chat }) {
                        demoOrca?.take(slot: slot, chat: found.id, status: found.status, title: found.title)
                    }
                case let .orcaFree(slot): demoOrca?.free(slot: slot)
                case .orcaShow: break
                default: demoSessions.apply(command)
                }
                bridge = demoBridge()
            }
            return
        }
        let socket = files.socket
        Task { [weak self] in
            let problem = await Task.detached { () -> String? in
                var refused: String?
                do {
                    try SocketClient.send(line, to: socket, timeout: timeout) { reply in
                        if let answer = JSONValue.parse(reply), answer["ok"]?.bool == false {
                            refused = answer["error"]?.string ?? "the bridge refused"
                        }
                        return false
                    }
                } catch {
                    refused = "the bridge did not answer"
                }
                return refused
            }.value
            if let problem { self?.notice = "Not done: \(problem)." }
            self?.refresh()
        }
    }

    /// The session keeps a key until it is unpinned or forgotten: key `slot` (0 to 5), or the
    /// key it has.
    func pin(_ session: SessionRow, to slot: Int? = nil) {
        var pairs: [(String, JSONValue)] = [("op", .string("pin")), ("session", .string(session.id))]
        if let slot { pairs.append(("slot", .number(Double(slot)))) }
        send(pairs)
    }

    func unpin(_ session: SessionRow) {
        send([("op", .string("unpin")), ("session", .string(session.id))])
    }

    /// The keys whose sessions are pinned.
    var pinnedSlots: Set<Int> {
        Set(bridge.sessions.compactMap { $0.pinned ? $0.slot : nil })
    }

    /// For screenshots: the window as it looks when the bridge does not answer.
    func showStopped() {
        guard isDemo else { return }
        bridge = BridgeSnapshot()
    }

    // MARK: Orca

    private func demoBridge() -> BridgeSnapshot {
        var demo = BridgeSnapshot.demo(demoSessions, orca: demoOrca.map { (layer: 2, keys: $0) })
        demo.layer = demoLayer
        return demo
    }

    /// For screenshots: Orca has layer 2, with made-up chats on four of its keys, one of them
    /// closed. `padThere` puts the pad on that layer.
    func showOrca(padThere: Bool = false) {
        guard isDemo else { return }
        let made: [(String, AgentStatus)] = [
            ("Fix the checkout total", .working), ("Write the release notes", .needsYou),
            ("Rename the billing tables", .done), ("Review the login flow", .idle), ("Plan the search page", .idle),
        ]
        orcaChats = made.enumerated().map { index, chat in
            OrcaChat(id: "demo-chat-\(index)", title: chat.0, worktree: "demo::/code/storefront", status: chat.1)
        }
        var keys = OrcaKeys()
        for (slot, chat) in orcaChats.prefix(4).enumerated() {
            keys.take(slot: slot, chat: chat.id, status: chat.status, title: chat.title)
        }
        keys.end(orcaChats[3].id)
        orcaChats.remove(at: 3)
        demoOrca = keys
        demoLayer = padThere ? 2 : LayerWatch.ours
        setChatGPTLayer(true)
        setOrcaLayer(true)
        bridge = demoBridge()
    }

    /// Asks the bridge for Orca's open chats, at most every few seconds: the bridge asks Orca.
    private func refreshOrcaChats() {
        guard !isDemo, !askingOrca, Date().timeIntervalSince(askedOrca) >= 4 else { return }
        askingOrca = true
        askedOrca = Date()
        let socket = files.socket
        Task { [weak self] in
            let chats = await Task.detached(priority: .utility) { Self.fetchOrcaChats(socket: socket) }.value
            guard let self else { return }
            self.askingOrca = false
            if self.orcaChats != chats { self.orcaChats = chats }
        }
    }

    private nonisolated static func fetchOrcaChats(socket: String) -> [OrcaChat] {
        var reply: JSONValue?
        try? SocketClient.send(#"{"op":"orca.chats"}"#, to: socket, timeout: 6) { line in
            reply = JSONValue.parse(line)
            return false
        }
        return reply.map(orcaChats(reply:)) ?? []
    }

    /// The chats in the bridge's answer to "orca.chats".
    nonisolated static func orcaChats(reply: JSONValue) -> [OrcaChat] {
        guard reply["ok"]?.bool == true, case let .array(items)? = reply["chats"] else { return [] }
        return items.compactMap { item in
            guard let id = item["session"]?.string, let title = item["title"]?.string else { return nil }
            return OrcaChat(id: id, title: title, worktree: item["worktree"]?.string ?? "",
                            status: AgentStatus(rawValue: item["status"]?.string ?? "") ?? .idle)
        }
    }

    /// What to call the chat on a key: its title in Orca, or the start of its ID while Orca
    /// has not said.
    func orcaTitle(_ key: OrcaKeyRow) -> String {
        orcaChats.first { $0.id == key.chat }?.title ?? key.title ?? "Chat " + key.chat.prefix(8)
    }

    /// The open chats that are on no key.
    var orcaChatsOffKeys: [OrcaChat] {
        let taken = Set(bridge.orca?.keys.map(\.chat) ?? [])
        return orcaChats.filter { !taken.contains($0.id) }
    }

    /// Puts a chat on an empty key of Orca's layer: `chat` by Orca's session ID, or the chat
    /// on screen in Orca, as a hold on the key does.
    func orcaTake(slot: Int, chat: String? = nil) {
        var pairs: [(String, JSONValue)] = [("op", .string("orca.take")), ("slot", .number(Double(slot)))]
        if let chat { pairs.append(("session", .string(chat))) }
        askedOrca = .distantPast
        send(pairs, timeout: 8)
    }

    /// The key lets its chat go, as a hold on a taken key does.
    func orcaFree(slot: Int) {
        send([("op", .string("orca.free")), ("slot", .number(Double(slot)))], timeout: 8)
    }

    /// Brings the key's chat on screen in Orca, as a tap on the key does.
    func orcaShow(slot: Int) {
        send([("op", .string("orca.show")), ("slot", .number(Double(slot)))], timeout: 8)
    }

    /// The layer the config gives Orca's chats, when it gives them one.
    var orcaLayer: Int? {
        config.layer(ofApp: Orca.bundleID).flatMap { $0 == LayerWatch.ours ? nil : $0 }
    }

    /// The layer on which the pad is ChatGPT's.
    var chatGPTLayer: Int? {
        config.layers.filter { $0.value == PadSharing.chatGPT }.keys.min()
    }

    /// Gives Orca layer 2, or takes its layer away. ChatGPT's layer moves out of the way and
    /// back: a layer is the bridge's own or another app's, not both.
    func setOrcaLayer(_ on: Bool) {
        let orca = orcaLayer, chatGPT = chatGPTLayer
        if on {
            guard orca == nil else { return }
            guard config.layerApps[2] == nil else {
                notice = "Not done: layer 2 is given to other apps in the config file."
                return
            }
            edit { file in
                if chatGPT == 2 {
                    file.set(nil, at: ["layers", "2"])
                    file.set(.string(PadSharing.chatGPT), at: ["layers", "3"])
                }
                file.set(.array([.string("orca")]), at: ["layerApps", "2"])
            }
        } else if let orca {
            edit { file in
                file.set(nil, at: ["layerApps", String(orca)])
                if let chatGPT, chatGPT == orca + 1 {
                    file.set(nil, at: ["layers", String(chatGPT)])
                    file.set(.string(PadSharing.chatGPT), at: ["layers", String(orca)])
                }
            }
        }
    }

    /// Passes the pad to ChatGPT on the first layer the bridge does not drive itself, or
    /// stops passing it.
    func setChatGPTLayer(_ on: Bool) {
        let now = chatGPTLayer
        if on {
            guard now == nil, let free = (2 ... 9).first(where: { config.layerApps[$0] == nil && config.layers[$0] == nil }) else { return }
            set(.string(PadSharing.chatGPT), at: ["layers", String(free)])
        } else if let now {
            set(nil, at: ["layers", String(now)])
        }
    }

    func session(onSlot slot: Int) -> SessionRow? {
        bridge.sessions.first { $0.slot == slot }
    }

    var waiting: [SessionRow] {
        bridge.sessions.filter { $0.slot == nil }
    }

    /// Shows a Claude app session, the way a tap on its Agent Key does.
    func open(_ session: SessionRow) {
        guard !isDemo, let host = session.host, host.hasPrefix("claude:"),
              let url = URL(string: "claude://code/continue?session=" + host.dropFirst("claude:".count)) else { return }
        NSWorkspace.shared.open(url)
    }

    func forget(_ session: SessionRow) {
        send([("op", .string("forget")), ("session", .string(session.id))])
    }

    func restartBridge() {
        guard !isDemo else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/local.micro-bridge"]
        do {
            try process.run()
        } catch {
            notice = "Could not restart the bridge: \(error.localizedDescription)"
        }
    }

    func openPrivacySettings(_ pane: String) {
        guard !isDemo, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInEditor(_ path: String) {
        guard !isDemo else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", path]
        try? process.run()
    }

    /// The one thing to do next, or nil when everything works.
    var nextStep: NextStep? {
        if !bridge.running {
            switch loginStart {
            case .off:
                return NextStep(text: "The bridge is not running. Start it now, and every time you log in.",
                                button: "Start at login") { [weak self] in self?.startAtLogin() }
            case .needsApproval:
                return NextStep(text: "macOS is waiting for you to allow MicroBridge under Login Items.",
                                button: "Open Login Items") { [weak self] in self?.openLoginItems() }
            default:
                return NextStep(text: "The bridge is not running.", button: "Start it") { [weak self] in self?.restartBridge() }
            }
        }
        if let access = bridge.inputMonitoring, access != InputMonitoring.granted.rawValue {
            return NextStep(text: "macOS does not let MicroBridge read the pad yet. Switch it on under Input Monitoring.",
                            button: "Open Settings") { [weak self] in self?.openPrivacySettings("Privacy_ListenEvent") }
        }
        if bridge.accessibility == false {
            return NextStep(text: "macOS does not let MicroBridge press keys and buttons yet. Switch it on under Accessibility.",
                            button: "Open Settings") { [weak self] in self?.openPrivacySettings("Privacy_Accessibility") }
        }
        if !problems.isEmpty {
            return NextStep(text: "The config file has a problem, so the last good settings stay in use.",
                            button: "Open the file") { [weak self] in
                guard let self else { return }
                self.openInEditor(self.files.config)
            }
        }
        if hookEvents == 0 {
            return NextStep(text: "Claude Code does not report to the bridge yet. Run the copied command in Terminal, or add the MicroBridge plugin in Claude Code.",
                            button: "Copy the command") { [weak self] in self?.copyHookCommand() }
        }
        if !bridge.connected {
            return NextStep(text: "The pad is not connected. Plug it in with its USB cable.")
        }
        if let layer = bridge.layer, !config.isOwn(layer: layer) {
            return NextStep(text: "The pad is on layer \(layer), where its keys are off. Tap the touch sensor on its bottom-left edge.")
        }
        return nil
    }

    // MARK: The config file

    private func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func loadConfig() {
        let stamp = modified(files.config)
        guard !loaded || stamp != fileStamp else { return }
        loaded = true
        fileStamp = stamp
        guard let data = FileManager.default.contents(atPath: files.config) else {
            // No file: the bridge runs on its defaults, and the first change writes one.
            file = defaults
            config = .builtIn
            problems = []
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        file = ConfigFile(text: text)
        do {
            config = try Config.parse(text)
            problems = []
        } catch {
            problems = error.description.split(separator: "\n").map(String.init)
        }
    }

    /// Changes the file. A change the bridge would refuse is not written, and `notice` says why.
    func edit(_ change: (inout ConfigFile) -> Void) {
        guard var next = file else {
            notice = "The config file is not valid JSON. Open it in an editor and fix it first."
            return
        }
        change(&next)
        guard next != file else { return }
        let text = next.text
        do {
            config = try Config.parse(text)
        } catch {
            notice = "Not saved. " + error.description
            return
        }
        file = next
        problems = []
        notice = nil
        unsaved = text
        saving?.cancel()
        // A slider or a color well changes many times a second; write once it rests.
        saving = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Writes a waiting change now. The app calls this before it quits.
    func save() {
        saving?.cancel()
        guard !isDemo, let text = unsaved else { return }
        unsaved = nil
        let manager = FileManager.default
        let backup = files.config + ".before-app"
        do {
            try manager.createDirectory(atPath: (files.config as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
            // The first save rewrites the file's layout, so keep the file as the person wrote it.
            if manager.fileExists(atPath: files.config), !manager.fileExists(atPath: backup) {
                try manager.copyItem(atPath: files.config, toPath: backup)
            }
            try text.write(toFile: files.config, atomically: true, encoding: .utf8)
            fileStamp = modified(files.config)
        } catch {
            notice = "Could not save the config file: \(error.localizedDescription)"
        }
    }

    func set(_ value: JSONValue?, at path: [String]) {
        edit { $0.set(value, at: path) }
    }

    /// What the file says at `path`, or the default when the file leaves it out.
    func value(at path: [String]) -> (value: JSONValue?, isDefault: Bool) {
        let standard = defaults?.value(at: path)
        if let own = file?.value(at: path) { return (own, own == standard) }
        return (standard, true)
    }

    // MARK: Keys

    func keycap(_ key: String) -> (cap: Keycap, isDefault: Bool) {
        let found = value(at: ["keys", key])
        guard let value = found.value else { return (.nothing, found.isDefault) }
        if case .object = value { return (.custom(value.serialized), found.isDefault) }
        // A list of one is the same as that one action.
        let actions = Self.spellings(value)
        if actions.isEmpty { return (.nothing, found.isDefault) }
        if actions.count == 1, case let .command(name, _)? = Action.parse(actions[0]) {
            return (.command(name), found.isDefault)
        }
        return (.custom(value.string ?? value.serialized), found.isDefault)
    }

    /// Makes a whole key one command, or nothing when `name` is nil.
    func setKeycap(_ key: String, to name: String?) {
        set(.string(name.map { "cmd:" + $0 } ?? "none"), at: ["keys", key])
    }

    func resetKey(_ key: String) {
        set(nil, at: ["keys", key])
    }

    /// The triggers of a control that is one section of the file: agentKeys, dial or stick.
    func triggers(of section: String) -> [(String, JSONValue)] {
        let found = value(at: [section]).value
        if case let .object(pairs)? = found { return pairs }
        // "agentKeys" may be a bare action or a list, which means its press.
        if let found, section == "agentKeys" { return [("press", found)] }
        return []
    }

    func trigger(_ trigger: String, of section: String) -> JSONValue? {
        triggers(of: section).first { $0.0 == trigger }?.1
    }

    /// A section the file mentions replaces every trigger of that control, so this writes all of them.
    func setTrigger(_ trigger: String, of section: String, to value: JSONValue?) {
        var pairs = triggers(of: section)
        if let index = pairs.firstIndex(where: { $0.0 == trigger }) {
            if let value { pairs[index].1 = value } else { pairs.remove(at: index) }
        } else if let value {
            pairs.append((trigger, value))
        }
        set(.object(pairs), at: [section])
    }

    /// What turning the dial runs, read from its two turns in either order.
    var dialTurn: DialTurn {
        let turns = Set([trigger("cw", of: "dial"), trigger("ccw", of: "dial")].map { $0?.string })
        if turns == ["cmd:PREV", "cmd:NEXT"] { return .answers }
        if turns == ["cmd:BACK", "cmd:FORWARD"] { return .sessions }
        return .own
    }

    /// Sets both turns of the dial in one write. Its press and hold are kept.
    func setDialTurn(_ turn: DialTurn) {
        guard turn != dialTurn, let (cw, ccw) = turn.commands else { return }
        var pairs = triggers(of: "dial")
        for (name, value) in [("cw", cw), ("ccw", ccw)] {
            if let index = pairs.firstIndex(where: { $0.0 == name }) {
                pairs[index].1 = .string(value)
            } else {
                pairs.append((name, .string(value)))
            }
        }
        set(.object(pairs), at: ["dial"])
    }

    func sectionIsDefault(_ section: String) -> Bool {
        value(at: [section]).isDefault
    }

    func swapDial() {
        guard let left = trigger("cw", of: "dial"), let right = trigger("ccw", of: "dial") else { return }
        var pairs = triggers(of: "dial")
        for index in pairs.indices {
            if pairs[index].0 == "cw" { pairs[index].1 = right }
            if pairs[index].0 == "ccw" { pairs[index].1 = left }
        }
        set(.object(pairs), at: ["dial"])
    }

    // MARK: Commands

    /// Commands that do something, by name.
    var commandNames: [String] {
        config.commands.filter { _, targets in targets.values.contains { $0.values.contains { !$0.isEmpty } } }
            .keys.sorted { title($0).localizedCaseInsensitiveCompare(title($1)) == .orderedAscending }
    }

    func title(_ command: String) -> String {
        Config.commandTitles[command] ?? command
    }

    /// What goes on the drawing of each lower key, by the key's name in the file.
    var legends: [String: String] {
        Dictionary(uniqueKeysWithValues: PadControl.keyTitles.keys.map { ($0, legend($0)) })
    }

    /// What goes on the drawing of a key.
    func legend(_ key: String) -> String {
        switch keycap(key).cap {
        case let .command(name): Config.commandTitles[name].map { $0.split(separator: " ").first.map(String.init) ?? $0 } ?? name
        case .nothing: ""
        case .custom: "Custom"
        }
    }

    /// What the drawing prints on each lower key, by the key's name in the file.
    var faces: [String: KeyFace] {
        Dictionary(uniqueKeysWithValues: PadControl.keyTitles.keys.map { ($0, face($0)) })
    }

    /// What each lower key runs, in words, by the key's name in the file.
    var keyNames: [String: String] {
        Dictionary(uniqueKeysWithValues: PadControl.keyTitles.keys.map { key in
            switch keycap(key).cap {
            case let .command(name): (key, title(name))
            case .nothing: (key, "nothing")
            case .custom: (key, "its own actions")
            }
        })
    }

    func face(_ key: String) -> KeyFace {
        switch keycap(key).cap {
        case let .command(name): face(ofCommand: name)
        case .nothing: .blank
        case .custom: .symbol("slider.horizontal.3")
        }
    }

    /// A picture for a command that has one, else the first letters of its name.
    func face(ofCommand name: String) -> KeyFace {
        Self.symbols[name].map(KeyFace.symbol) ?? .text(String(name.prefix(3)))
    }

    /// SF Symbols, chosen for this window. None is a logo or the pad's own artwork.
    static let symbols: [String: String] = [
        "APPR": "checkmark.circle", "REJ": "xmark.circle", "NEW": "square.and.pencil", "SPLIT": "arrow.triangle.branch",
        "MIC": "mic", "CODEX": "arrow.up.circle", "FAST": "bolt", "PLAN": "checklist", "FORWARD": "chevron.right",
        "BACK": "chevron.left", "SIDEBAR": "sidebar.left", "NEXT": "arrow.down", "PREV": "arrow.up", "PICK": "return",
        "PADSETTINGS": "gearshape.2", "SETUP": "gearshape", "LAB": "flask", "BUG": "ladybug", "OAI": "book",
        "TERM": "terminal", "DWN": "arrow.down.to.line", "DEL": "trash", "NAV": "location", "MAGIC": "sparkles",
        "DIFF": "plusminus", "PLAY": "play", "GIT": "smallcircle.filled.circle", "BRANCH": "point.topleft.down.to.point.bottomright.curvepath",
        "MRG": "arrow.triangle.merge", "PR": "arrow.triangle.pull", "BRCH": "pencil.line", "PAINT": "paintbrush",
        "PARTY": "party.popper", "TIME": "clock", "MIND+": "plus.circle", "MIND-": "minus.circle",
        "FOLD": "folder.badge.plus", "UPL": "square.and.arrow.up", "APPS": "square.grid.2x2", "COMPUTER": "desktopcomputer",
        "MIC1": "mic", "LOCK": "lock",
    ]

    var claudeApp: String? { config.apps["claude"]?.first }
    var terminalApp: String? { config.apps["terminal"]?.first }

    /// What a control does on a trigger, in the Claude app and in a terminal.
    func does(_ control: String, _ trigger: String) -> (claude: [Action], terminal: [Action]) {
        (config.actions(for: control, trigger, app: claudeApp), config.actions(for: control, trigger, app: terminalApp))
    }

    var colorsAreDefault: Bool {
        value(at: ["lighting", "colors"]).isDefault
    }

    // MARK: Lights

    func rgb(_ status: AgentStatus) -> UInt32 {
        config.lighting.color(status)
    }

    func setColor(_ status: AgentStatus, to rgb: UInt32) {
        guard rgb != self.rgb(status) else { return }
        set(.string(String(format: "#%06X", rgb)), at: ["lighting", "colors", status.rawValue])
    }

    func resetColors() {
        set(nil, at: ["lighting", "colors"])
    }
}

extension AgentStatus {
    var label: String {
        switch self {
        case .working: "Working"
        case .needsYou: "Needs you"
        case .idle: "Idle"
        case .done: "Done, not read"
        case .failed: "Failed"
        case .off: "No session"
        }
    }

    var meaning: String {
        switch self {
        case .working: "The session is busy."
        case .needsYou: "A permission prompt or a question is waiting."
        case .idle: "The session waits for your next prompt."
        case .done: "The session finished and you have not acted on it."
        case .failed: "The turn ended with an error."
        case .off: "No session holds this key."
        }
    }
}
