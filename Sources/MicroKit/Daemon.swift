import AppKit
import Foundation

/// What the daemon reaches outside itself for. Tests put a fake pad and a scratch folder here.
struct DaemonWorld {
    /// Where the socket, the config and the saved sessions live.
    var directory = BridgePaths.directory
    var openPad: @MainActor () throws(PadError) -> Pad = { () throws(PadError) -> Pad in try Pad.open() }
    var findHelper: @MainActor () -> Pad.HelperAttempt = { Pad.throughHelper() }
    /// The bundle id of the app in front, and of every running app.
    var frontApp: @MainActor () -> String? = { ActionRunner.frontApp }
    var runningApps: @MainActor () -> Set<String> = {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
    var askForAccessibility: @MainActor () -> Void = { _ = Accessibility.request() }
    /// A macOS notification: its title, then its text.
    var notify: @MainActor (String, String) -> Void = { Daemon.notification(title: $0, text: $1) }
    /// What people call the app with that bundle id.
    var appName: @MainActor (String) -> String = { Daemon.name(ofApp: $0) }
    var log: @MainActor (String) -> Void = { print(ISO8601DateFormatter().string(from: Date()), $0) }
    /// Scrolls what is under the pointer by that many points, positive up. Nil: as a mouse
    /// wheel does. Tests count the points here, so that nothing on screen moves.
    var scroll: (@MainActor (Double) -> Void)?
    /// How the bridge asks Orca about its chats, and shows one.
    var orca = OrcaLink()

    var socket: String { directory + "/daemon.sock" }
    var config: String { directory + "/config.json" }
    var sessions: String { directory + "/sessions.json" }
    /// The chats on the keys of Orca's layer.
    var orcaKeys: String { directory + "/orca-keys.json" }
}

/// Owns the pad. Keeps the six Agent Keys showing `state`, repaints after every reconnect,
/// runs the actions the user's config binds to each control, and relays raw events to
/// subscribed socket clients.
@MainActor
public final class Daemon {
    private var state = BridgeState()
    /// The chats on the keys of Orca's layer, put there by hand.
    private(set) var orca = OrcaKeys()
    /// Said once: a chat in Orca reported while no layer is Orca's.
    private var saidNoOrcaLayer = false
    private var config = Config.builtIn
    private var configStamp: Date?
    private var configRead = false
    private var gestures = Gestures()
    private let runner = ActionRunner()
    private var clickGuard = ClickGuard(seconds: 1)
    /// Per session, the change time of its record when it was last read.
    private var recordRead: [String: Date] = [:]
    /// The Agent Key pressed last; command keys act on its session.
    private var selected: Int?
    /// The sessions the Claude app's windows show; their keys pulse. Read once a second.
    private var shown: [SessionHost] = []
    /// After a slow answer from the Claude app, when to ask it again.
    private var askShownAfter: Date?
    /// The keys that pulse for it, as last written to the pad.
    private var pulsing: Set<Int> = []
    private var lastActivity = Date()
    private var dimmed = false
    /// macOS is turning writes to the pad away, as it does while the Mac is locked.
    private var refused = false
    /// What started a lock the lights went off for. They stay off until the Mac is unlocked.
    private enum LockStart: String {
        case pad = "the pad's lock"
        case shortcut = "⌃⌘Q"
    }

    private var lockStart: LockStart?
    /// Catches ⌃⌘Q while `lighting.offWhenLocked` is on.
    private lazy var shortcut = LockShortcut { [weak self] in self?.lock(from: .shortcut) }
    /// ⌃⌘Q was caught once and the Mac did not lock: it passes untouched until a restart.
    private var shortcutFailed = false
    private var warnedShortcut = false
    /// When the pad asked, and whether macOS has said since that the Mac is locked.
    private var lockAskedAt: Date?
    private var lockSeen = false
    private var lockObservers: [NSObjectProtocol] = []
    private var askedForAccessibility = false
    /// When an empty Agent Key was pressed to start a session on it.
    private var reservedAt: Date?
    /// Light writes in a row that the pad took but did not answer, and when to try again.
    private var unanswered = 0
    private var retryAt: Date?
    /// The pad's last answer to `device.status`, and the layer it put the pad on.
    private var padStatus: DeviceStatus?
    private var layers = LayerWatch()
    /// The layer the bridge last acted on. See `actingLayer`.
    private var actedLayer = LayerWatch.ours
    private var battery = BatteryWatch(threshold: 20)

    private var pad: Pad?
    /// Who acts on the pad while another app, such as ChatGPT, has it open too.
    private var sharing = PadSharing(apps: [])
    private var frontObserver: NSObjectProtocol?
    /// When a repaint over another app's light write was last logged.
    private var otherPaintLogged: Date?
    /// When the pad last sent a report as a keyboard or mouse would (system uptime).
    private var typedAt: TimeInterval?
    /// Reads the layer often while a tap back to the first layer is due, and how many
    /// readings it has left.
    private var quickLayer: Timer?
    private var quickReadsLeft = 0
    /// Reads the layer four times a second while one tap can change who has the pad.
    private var steadyLayer: Timer?
    /// The last reason holding the pad failed, said once, and when to try again.
    private var holdProblem: String?
    private var holdRetryAt: TimeInterval = 0
    /// Why MicroBridge Helper last turned the bridge away, said once.
    private var helperRefusal: String?
    private let server: SocketServer
    private var dirty = true
    private var flushing = false
    private var lastProblem: String?
    private var timer: Timer?
    private var holdTimer: Timer?
    /// The stick scrolling: its speed in points a second (positive up), the clock of the last
    /// step and of the stick's last word, and what this push has done so far.
    private var scroller = StickScroll()
    private var scrollTimer: Timer?
    private var scrollSpeed = 0.0
    private var scrollStepAt: TimeInterval = 0
    private var stickHeardAt: TimeInterval = 0
    private var scrollPush = (since: 0.0, reports: 0, up: 0.0, down: 0.0)
    private var ticks = 0
    private var signalSources: [DispatchSourceSignal] = []

    private let world: DaemonWorld

    public convenience init() throws(SocketError) {
        try self.init(world: DaemonWorld())
    }

    init(world: DaemonWorld) throws(SocketError) {
        self.world = world
        server = try SocketServer(directory: world.directory, socket: world.socket)
        server.onLine = { [weak self] client, line in self?.handle(line, from: client) }
        runner.log = { [weak self] message in self?.log(message) }
    }

    /// Runs forever.
    public func run() -> Never {
        log("micro daemon started, listening on \(world.socket)")
        log("typing keys into apps: \(Accessibility.granted ? "allowed" : "not allowed yet")")
        loadConfig()
        restoreSessions()
        restoreOrcaKeys()
        connect()
        watchLock()
        watchFront()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Turn the lights off on the way out, as the vendor app does.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.saveSessions()
                    // While ChatGPT has the pad, the lights are its own.
                    if self?.sharing.asideFor == nil { try? self?.pad?.allOff() }
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
        while true { CFRunLoopRun() }
    }

    private func log(_ message: String) {
        world.log(message)
    }

    // MARK: Config

    /// Reads the config file when it is new or has changed. A broken file keeps the last good one.
    private func loadConfig() {
        let path = world.config
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard !configRead || stamp != configStamp else { return }
        configRead = true
        configStamp = stamp
        do {
            config = try Config.load(path)
            log(stamp == nil ? "no config file, using the built-in defaults"
                : "config loaded from \(path): \(config.bindings.count) bindings")
        } catch {
            log("config has problems, keeping the previous settings:\n\(error.description)")
        }
        runner.keystrokeApps = config.keystrokeApps
        clickGuard.seconds = config.clickGuard
        state.urgentFirst = config.urgentFirst
        state.rememberSeconds = config.rememberHours * 3600
        battery.threshold = config.batteryWarning
        sharing.apps = config.stepAsideFor
        sharing.layers = config.layers
        sharing.layerKeys = config.layerKeys
        sharing.own = config.ownLayers
        _ = layerActedOn()
        frontChanged(world.frontApp())
        if config.typesKeys || config.lighting.offWhenLocked, !Accessibility.granted, !askedForAccessibility {
            askedForAccessibility = true
            log("the config types keys or catches ⌃⌘Q: allow MicroBridge under Privacy & Security > Accessibility")
            world.askForAccessibility()
        }
        watchShortcut()
        dirty = true
        flush()
    }

    // MARK: Commands, for the panel in Orca

    /// The config file as it is on disk, or an empty one when there is none. Nil when the
    /// file is not a JSON object.
    private func configFile() -> ConfigFile? {
        guard let text = try? String(contentsOfFile: world.config, encoding: .utf8) else { return ConfigFile(text: "{}") }
        return ConfigFile(text: text)
    }

    /// What the commands do in `target`: every command a control runs, then every other one
    /// that has an entry for that target. The panel in Orca shows them and changes them.
    func commands(in target: String) -> [Reply.CommandRow] {
        let file = configFile() ?? ConfigFile.builtIn
        let order = ["AG"] + Config.keyControls + ["DIAL", "STICK"]
        var controls: [String: [String]] = [:]
        for (binding, actions) in config.bindings {
            guard let control = binding.split(separator: ".").first.map(String.init) else { continue }
            for case let .command(name, _) in actions where controls[name]?.contains(control) != true {
                controls[name, default: []].append(control)
            }
        }
        func place(_ control: String) -> Int { order.firstIndex(of: control) ?? order.count }
        let rows = config.commands.keys.compactMap { name -> Reply.CommandRow? in
            let here = file?.commandLists(name, target: target, defaults: ConfigFile.builtIn).filter { !$0.actions.isEmpty } ?? []
            let elsewhere = file?.commandLists(name, target: "default", defaults: ConfigFile.builtIn)
                .filter { !$0.actions.isEmpty } ?? []
            let runBy = (controls[name] ?? []).sorted { place($0) < place($1) }
            guard !runBy.isEmpty || !here.isEmpty else { return nil }
            return Reply.CommandRow(name: name, controls: runBy.map { Config.controlTitles[$0] ?? $0 }, here: here,
                                    elsewhere: elsewhere)
        }
        func first(_ row: Reply.CommandRow) -> Int { (controls[row.name] ?? []).map(place).min() ?? order.count + 1 }
        return rows.sorted { one, two in first(one) != first(two) ? first(one) < first(two) : one.name < two.name }
    }

    /// Writes what a command does on one trigger in one target to the config file, by the
    /// rule the MicroBridge window uses. Returns why it did not, or nil when it did.
    func setCommand(_ name: String, target: String, trigger: String = "press", actions: [String]) -> String? {
        guard config.commands[name] != nil else { return "no command named \(name)" }
        for text in actions {
            guard let action = Action.parse(text) else { return "\(text): not an action the bridge knows" }
            if case .command = action { return "\(text): a command cannot run another command" }
        }
        guard var file = configFile() else { return "the config file is not valid JSON: fix it in an editor first" }
        let before = file
        file.setCommand(name, target: target, trigger: trigger, actions: actions, defaults: ConfigFile.builtIn)
        guard file != before else { return nil }
        let text = file.text
        do {
            _ = try Config.parse(text)
        } catch {
            return "not saved: " + error.description
        }
        let manager = FileManager.default
        let path = world.config, backup = path + ".before-app"
        do {
            // The first save rewrites the file's layout, so keep the file as the person wrote it.
            if manager.fileExists(atPath: path), !manager.fileExists(atPath: backup) {
                try manager.copyItem(atPath: path, toPath: backup)
            }
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            return "could not save the config file: \(error.localizedDescription)"
        }
        log("command \(name): \(trigger) in \(target) changed over the socket")
        loadConfig()
        return nil
    }

    // MARK: Socket

    private func handle(_ line: String, from client: SocketServer.Client) {
        let command: Command
        do {
            command = try Command.parse(line)
        } catch {
            client.send(Reply.error(error.description))
            return
        }
        switch command {
        case .state:
            let access = Reply.Access(inputMonitoring: InputMonitoring.current, accessibility: Accessibility.granted)
            client.send(Reply.state(state, pad: pad?.info, status: padStatus, shown: shown, access: access,
                                    orca: orcaLayer.map { ($0, orca) }))
        case .subscribe:
            client.subscribed = true
            client.send(Reply.ok)
            client.send(Reply.connection(pad != nil))
        case .report, .end, .forget, .set, .clear:
            take(command) { client.send(Reply.ok) }
        case .orcaTake, .orcaFree, .orcaShow:
            orcaCommand(command) { problem in client.send(problem.map(Reply.error) ?? Reply.ok) }
            flush()
        case .orcaChats:
            orcaChats { client.send($0) }
        case let .commands(target):
            client.send(Reply.commands(commands(in: target)))
        case let .commandSet(name, target, trigger, actions):
            client.send(setCommand(name, target: target, trigger: trigger, actions: actions).map(Reply.error) ?? Reply.ok)
        case let .pin(id, _), let .unpin(id):
            guard state.sessions[id] != nil else {
                client.send(Reply.error("no session \"\(id)\""))
                return
            }
            if state.apply(command) { lightsChanged() }
            if case .pin = command, state.sessions[id]?.pinned != true {
                client.send(Reply.error("every key is pinned"))
            } else {
                client.send(Reply.ok)
            }
            // Now, not at the next save: a pin is the person's own choice.
            saveSessions()
            flush()
        }
    }

    /// Does what a session said, or a key painted by hand. `answered` runs before the lights
    /// are written, so whoever said it does not wait for the pad. Tests call it by hand.
    func take(_ command: Command, answered: () -> Void = {}) {
        switch command {
        case .orcaTake, .orcaFree, .orcaShow:
            orcaCommand(command) { _ in }
        default:
            if !orcaHeard(command), state.apply(command) { lightsChanged() }
        }
        answered()
        flush()
    }

    /// A conversation with the pad is under way. Its wait for the answer runs the main run
    /// loop, so a test can find itself in the middle of one after an `await`.
    var isBusy: Bool { flushing }

    /// One second has passed. The timer calls it; tests call it by hand.
    func tick() {
        ticks += 1
        loadConfig()
        // In case a notice of the app in front went missing.
        frontChanged(world.frontApp())
        // Every few seconds, forget sessions whose agent process has exited.
        if ticks % 5 == 0 {
            if state.prune(isAlive: ProcessTree.isAlive) { lightsChanged() }
            for chat in orca.gone(isAlive: ProcessTree.isAlive) { chatExited(chat) }
            saveSessions()
        }
        // A pressed key's hold on its session runs out by itself.
        if state.rebalance() { lightsChanged() }
        // A key held for a new session goes back to the pool if none shows up.
        if let since = reservedAt, state.reserved == nil || Date().timeIntervalSince(since) > 120 {
            state.reserve(nil)
            reservedAt = nil
        }
        let limit = config.lighting.autoDimSeconds
        if limit > 0, !dimmed, Date().timeIntervalSince(lastActivity) >= Double(limit) {
            dimmed = true
            dirty = true
        }
        // A lock that never came (Accessibility taken away, say) must not leave the lights off.
        if let start = lockStart, !lockSeen, !refused, let asked = lockAskedAt, Date().timeIntervalSince(asked) > 5 {
            lightsBack("the Mac did not lock within 5 s")
            if start == .shortcut {
                // The person pressed ⌃⌘Q to lock. If the bridge's own ⌃⌘Q does not lock the
                // Mac, theirs must not be held back again.
                shortcutFailed = true
                watchShortcut()
                notify(title: "⌃⌘Q did not lock the Mac", text: "MicroBridge lets it through untouched now. Press ⌃⌘Q again.")
            }
        }
        checkStopped()
        checkShown()
        flush()
        connect()
        // With `layers` set, a tap on the touch sensor passes the pad on: look often. With a
        // second layer of the bridge's own, a tap changes whose keys they are.
        if ticks % 5 == 0 || !config.layers.isEmpty || !config.ownLayers.isEmpty {
            checkLayer()
            // Accessibility may have been granted since.
            watchShortcut()
        }
        if ticks % 30 == 0 { tryHelper() }
        // ChatGPT may have started or quit, also while it had the pad.
        let before = sharing.reason
        let quit = sharing.running(world.runningApps())
        if let pass = quit.pass { passed(pass) }
        if let change = quit.change { sharingChanged(change, before: before) }
        updateHold()
        watchLayer()
    }

    /// Stopping a turn by hand fires no hook, so a busy or waiting session would keep its light
    /// for good. Its record says when that happened.
    private func checkStopped() {
        for session in state.watchable {
            guard let path = session.transcript, let heard = session.heard,
                  let changed = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  recordRead[session.id] != changed else { continue }
            recordRead[session.id] = changed
            // One second of slack: the hook and the record are stamped by different processes.
            guard let tail = Transcript.tail(of: path), let at = Transcript.interruptedAt(tail: tail),
                  at >= heard.addingTimeInterval(-1) else { continue }
            log("session \(session.id.prefix(8)) was stopped by hand: its key goes to idle")
            if state.stopped(session.id) { lightsChanged() }
        }
        for chat in orca.watchable {
            guard let path = chat.transcript, let heard = chat.heard,
                  let changed = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  recordRead[chat.id] != changed else { continue }
            recordRead[chat.id] = changed
            guard let tail = Transcript.tail(of: path), let at = Transcript.interruptedAt(tail: tail),
                  at >= heard.addingTimeInterval(-1) else { continue }
            log("chat \(chat.id.prefix(8)) was stopped by hand: it is idle now")
            if orca.stopped(chat.id) { lightsChanged() }
        }
        recordRead = recordRead.filter { state.sessions[$0.key] != nil || orca.chats[$0.key] != nil }
    }

    /// The lights are off now: after a quiet spell, or for a lock.
    private var dark: Bool { dimmed || lockStart != nil }

    /// Catches ⌃⌘Q only while the setting is on. The tap needs Accessibility.
    private func watchShortcut() {
        let wanted = config.lighting.offWhenLocked && !shortcutFailed
        if wanted, !shortcut.started {
            shortcut.enabled = true
            guard shortcut.start() else {
                if !warnedShortcut {
                    warnedShortcut = true
                    log("cannot catch ⌃⌘Q: allow MicroBridge under Privacy & Security > Accessibility")
                }
                return
            }
            log("catching ⌃⌘Q: the lights go off before the Mac locks")
            return
        }
        guard shortcut.started, shortcut.enabled != wanted else { return }
        shortcut.enabled = wanted
        log(wanted ? "catching ⌃⌘Q again" : "⌃⌘Q passes untouched now")
    }

    /// Lights off while macOS still takes writes, then the lock. Once the Mac is locked macOS
    /// refuses every write, so the pad stays dark until the unlock.
    private func lock(from start: LockStart) {
        if start == .pad, !Accessibility.granted {
            log("cannot lock the Mac: allow MicroBridge under Privacy & Security > Accessibility")
            return
        }
        lockStart = start
        lockSeen = false
        lockAskedAt = Date()
        dirty = true
        lockWhenDark(start)
    }

    private func lockWhenDark(_ start: LockStart) {
        // A write already on its way must finish first, or the lock could beat the lights.
        if flushing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                MainActor.assumeIsolated { self?.lockWhenDark(start) }
            }
            return
        }
        flush()
        let dark = pad != nil && !dirty
        log("\(start.rawValue): " + (dark ? "lights off, locking the Mac" : "locking the Mac; the lights could not go off first"))
        switch start {
        case .pad: _ = runner.lockScreen()
        // The held-back ⌃⌘Q goes through now. It goes after 2.5 s anyway.
        case .shortcut: shortcut.darkened()
        }
    }

    /// macOS says when the Mac locks and unlocks, a moment after it has.
    private func watchLock() {
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.lockStart != nil else { return }
                    if locked {
                        self.lockSeen = true
                        // Keeps a write waiting, so the lights come back with the first one
                        // macOS lets through even if the unlock notice is missed.
                        self.dirty = true
                        self.flush()
                    } else {
                        self.lightsBack("the Mac is unlocked")
                    }
                }
            })
        }
    }

    private func lightsBack(_ why: String) {
        lockStart = nil
        lockAskedAt = nil
        log("\(why): the keys show their sessions again")
        // Back from the lock counts as use, so auto-dim starts its wait again.
        activity()
        dirty = true
        if refused { retryAt = nil }
        flush()
    }

    /// A status change or a touch of the pad wakes dimmed lights.
    private func activity() {
        lastActivity = Date()
        if dimmed {
            dimmed = false
            dirty = true
        }
    }

    private func lightsChanged() {
        dirty = true
        activity()
    }

    // MARK: Controls

    private func padEvent(_ event: PadEvent) {
        server.broadcast(Reply.event(event))
        act(on: event)
    }

    private func act(on event: PadEvent) {
        // The app the pad is left to hears this press too: it is that app's.
        guard sharing.asideFor == nil else { return }
        // Anything from the pad means it is listening again.
        if unanswered > 0 {
            retryAt = nil
            dirty = true
        }
        activity()
        let now = ProcessInfo.processInfo.systemUptime
        let app = world.frontApp()
        if case let .joystick(angle, distance) = event {
            if let its = otherLayer(of: app) {
                stopScrolling(why: "\(app ?? "the app in front") is layer \(its)'s and the pad is on layer \(actingLayer)")
            } else {
                stickMoved(angle: angle, distance: distance, app: app, at: now)
            }
        }
        // An Agent Key that does something when held presses when it comes up, so that
        // holding it does not open its session first.
        // On Orca's layer a hold takes a chat or frees the key, whatever `agentKeys` says.
        let orcaKeys = actingLayer == orcaLayer
        let fired = gestures.handle(event, at: now, waitsForHold: { [config] control in
            control == "AG" && (orcaKeys || !config.actions(for: control, "hold", app: app).isEmpty)
        }, hasDoubleTap: { [config] control in
            !(orcaKeys && control == "AG") && config.hasDoubleTap(control, app: app)
        })
        for one in fired { perform(one) }
        if gestures.hasKeysDown, holdTimer == nil {
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.holdTick() }
            }
        }
        flush()
    }

    private func holdTick() {
        for fired in gestures.tick(at: ProcessInfo.processInfo.systemUptime) { perform(fired) }
        if !gestures.hasKeysDown {
            holdTimer?.invalidate()
            holdTimer = nil
        }
        flush()
    }

    // MARK: Scrolling with the stick

    /// Which way the stick's `scroll:` action for `way` scrolls in `app`: +1 up, -1 down, nil
    /// when the stick does something else that way.
    private func stickScrolls(_ way: String, app: String?) -> Double? {
        for action in config.actions(for: "STICK", way, app: app) {
            if case let .scroll(up) = action { return up ? 1 : -1 }
        }
        return nil
    }

    /// Every report from the stick sets the scroll speed; the timer does the scrolling between
    /// reports, so a steady push scrolls steadily.
    private func stickMoved(angle: Double, distance: Double, app: String?, at now: TimeInterval) {
        guard let asked = StickScroll.speed(angle: angle, distance: distance),
              let sign = stickScrolls(asked > 0 ? "up" : "down", app: app) else {
            stopScrolling()
            return
        }
        scrollSpeed = abs(asked) * sign
        stickHeardAt = now
        scrollPush.reports += 1
        guard scrollTimer == nil else { return }
        scrollPush = (since: now, reports: 1, up: 0, down: 0)
        scrollStepAt = now
        scroller.reset()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollTick() }
        }
    }

    private func scrollTick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - stickHeardAt > StickScroll.silence {
            stopScrolling(why: String(format: "no word from the stick for %.0f s", StickScroll.silence))
            return
        }
        // A step held up by a busy main thread does not scroll in one jump.
        let points = scroller.step(speed: scrollSpeed, seconds: min(now - scrollStepAt, 0.1))
        scrollStepAt = now
        guard points != 0 else { return }
        if let scroll = world.scroll { scroll(points) } else { runner.scroll(points) }
        if points > 0 { scrollPush.up += points } else { scrollPush.down -= points }
    }

    private func stopScrolling(why: String = "let go") {
        guard let timer = scrollTimer else { return }
        timer.invalidate()
        scrollTimer = nil
        let took = ProcessInfo.processInfo.systemUptime - scrollPush.since
        let moved = [(scrollPush.up, "up"), (scrollPush.down, "down")].filter { $0.0 > 0 }
            .map { "\(Int($0.0)) points \($0.1)" }.joined(separator: ", ")
        log(String(format: "STICK scrolled %@ in %.1f s (%d reports from the stick), %@",
                   moved.isEmpty ? "nothing" : moved, took, scrollPush.reports, why))
    }

    private func perform(_ fired: Gestures.Fired) {
        let layer = actingLayer
        if let pressed = fired.slot, layer != LayerWatch.ours {
            // The sessions on the first layer's keys are not this layer's. Orca's layer has
            // its chats; any other layer of the bridge's own has no agents.
            if layer == orcaLayer {
                orcaKey(pressed, fired.trigger, layer: layer)
            } else if fired.trigger == "press" {
                log("AG.press key \(pressed + 1) on layer \(layer): no agent on this key, nothing to do")
            }
            return
        }
        if let slot = fired.slot, state.owner(of: slot) != nil, selected != slot {
            selected = slot
        }
        var trigger = fired.trigger
        if let pressed = fired.slot, state.owner(of: pressed) == nil {
            // An Agent Key with no session: only a press can do something, and only if the
            // config gives `agentKeys.empty` an action.
            guard trigger == "press" else { return }
            trigger = "empty"
        } else if trigger == "press", let pressed = fired.slot {
            state.touch(slot: pressed)
        }
        let app = world.frontApp()
        let actions = config.actions(for: fired.control, trigger, app: app)
        // The stick scrolls for as long as it is pushed (`stickMoved`); a step here would add a jump.
        if fired.control == "STICK", actions.contains(where: { if case .scroll = $0 { true } else { false } }) {
            return
        }
        guard !actions.isEmpty else {
            if trigger == "empty", let pressed = fired.slot { log("AG.press key \(pressed + 1): no session on this key, nothing to do") }
            return
        }
        // Layers are isolated: a control does nothing in an app of another layer. An Agent
        // Key still acts, since it brings its own app to the front.
        if fired.slot == nil, let its = otherLayer(of: app) {
            log("\(fired.control).\(trigger) does nothing: \(app ?? "the app in front") is layer \(its)'s and the pad is on layer \(layer)")
            return
        }
        // By trigger, so a dial press that clicked a card's "Next" does not silence the turns after it.
        let guarded = "\(fired.control).\(trigger)#\(fired.slot ?? -1)"
        if clickGuard.blocks(guarded) {
            log("\(fired.control).\(trigger) ignored: this key's click landed under \(config.clickGuard) s ago")
            return
        }
        if trigger == "empty", let pressed = fired.slot {
            state.reserve(pressed)
            reservedAt = Date()
        }
        // The key pressed last is a key of the first layer.
        let slot = fired.slot ?? (layer == LayerWatch.ours ? selected : nil)
        let session = slot.flatMap { state.owner(of: $0) }
        let key = fired.slot.map { " key \($0 + 1)" } ?? ""
        let names = actions.map(\.description).joined(separator: ", ")
        log("\(fired.control).\(trigger)\(key) in \(app ?? "no app"): \(names)")
        list: for action in actions {
            switch action {
            case .none:
                break
            case .ack:
                if let slot, state.acknowledge(slot: slot) { dirty = true }
            case .forget:
                if let slot, let owner = state.owner(of: slot) {
                    if state.apply(.forget(session: owner.id)) { lightsChanged() }
                    if selected == slot { selected = nil }
                }
            case .lock:
                lock(from: .pad)
                break list
            case .pin:
                if let slot, let owner = state.owner(of: slot) {
                    if owner.pinned { state.unpin(owner.id) } else { state.pin(owner.id) }
                    // The pad's only way to answer: twice dark for pinned, once for unpinned.
                    blink(slot, times: owner.pinned ? 1 : 2)
                    saveSessions()
                }
            default:
                // A click that found its button is the whole answer to the press.
                if runner.run(action, slot: slot, session: session) {
                    // Only a click earns the quiet time: a dial must keep stepping.
                    if case .click = action { clickGuard.landed(guarded) }
                    // A button pressed in the Claude app is an action on the session it shows:
                    // what that session finished counts as read.
                    if fired.slot == nil, let app, config.apps["claude"]?.contains(app) == true {
                        for read in state.acknowledge(showing: shown) {
                            log("key \(read + 1) counts as read: a button was pressed in its session")
                            dirty = true
                        }
                    }
                    break list
                }
            }
        }
    }

    // MARK: Pad

    private func connect() {
        guard pad == nil else { return }
        do {
            adopt(try world.openPad())
        } catch {
            // Say each problem once, not every second.
            if lastProblem != error.description {
                lastProblem = error.description
                log(error.description)
            }
        }
    }

    /// While the pad is open directly, MicroBridge Helper may have been installed, started or
    /// let in since: move over to it then.
    private func tryHelper() {
        guard let old = pad, !old.canHold, !flushing else { return }
        switch world.findHelper() {
        case let .connected(opened):
            pad = nil
            old.close()
            log("moving the pad over to MicroBridge Helper")
            adopt(opened)
        case let .refused(reason):
            if helperRefusal != reason {
                helperRefusal = reason
                log("MicroBridge Helper is installed but not in use: \(reason)")
            }
        case .absent:
            break
        }
    }

    private func adopt(_ opened: Pad) {
        opened.onEvent = { [weak self] event in self?.padEvent(event) }
        opened.onOtherReply = { [weak self] _, method in self?.otherAppAnswered(method) }
        opened.onOtherInput = { [weak self] in self?.padTyped() }
        opened.onUnreadable = { [weak self] text in
            self?.log("pad sent text that is not a message, skipped (\(text.utf8.count) bytes): \(text.prefix(160))")
        }
        opened.onDisconnect = { [weak self, weak opened] in
            // Not from inside the device's own callback.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let opened, self.pad === opened else { return }
                    self.drop("disconnected")
                }
            }
        }
        pad = opened
        lastProblem = nil
        unanswered = 0
        refused = false
        retryAt = nil
        log("pad connected: \(opened.info.model) over \(opened.info.transport)"
            + (opened.canHold ? ", through MicroBridge Helper" : ""))
        if let note = opened.helperNote, helperRefusal != note {
            helperRefusal = note
            log("MicroBridge Helper is installed but not in use: \(note)")
        }
        if opened.canHold { helperRefusal = nil }
        holdProblem = nil
        holdRetryAt = 0
        server.broadcast(Reply.connection(true))
        dirty = true
        flush()
        checkLayer()
        updateHold()
    }

    private func drop(_ reason: String) {
        guard let old = pad else { return }
        pad = nil
        padStatus = nil
        layers.reset()
        actedLayer = LayerWatch.ours
        // The next pad's first reading is where it starts, not a visit. Who has the pad stays.
        _ = sharing.layer(nil, running: [])
        quickLayer?.invalidate()
        quickLayer = nil
        steadyLayer?.invalidate()
        steadyLayer = nil
        old.close()
        log("pad \(reason)")
        server.broadcast(Reply.connection(false))
    }

    // MARK: Sharing the pad

    private func watchFront() {
        frontObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontChanged(app) }
        }
    }

    private func frontChanged(_ app: String?) {
        let before = sharing.reason
        guard let change = sharing.front(app) else { return }
        sharingChanged(change, before: before)
    }

    /// The bridge leaves the pad to another app now, or has it back.
    private func sharingChanged(_ change: PadSharing.Change, before: PadSharing.Reason?) {
        switch change {
        case let .aside(id):
            // A push or a hold that started before the switch ends here.
            stopScrolling(why: "\(id) has the pad now")
            gestures = Gestures()
            holdTimer?.invalidate()
            holdTimer = nil
            var visited = false
            if case let .visit(layer) = sharing.reason {
                visited = true
                log("a visit to layer \(layer) passed the pad to \(id): the bridge leaves the pad to it, no lights and no key actions")
            } else if case let .layer(layer) = sharing.reason {
                visited = true
                log("the pad is on layer \(layer): the bridge leaves the pad to \(id), no lights and no key actions")
            } else {
                log("\(id) is in front: the bridge leaves the pad to it, no lights and no key actions")
            }
            // A held pad shut that app out, and it takes up to 10 s to open the pad again.
            // The Agent Keys go dark until then, so its own lights coming on say it is
            // listening. After a visit, or on that app's layer, they go dark without a hold
            // too: the keys are that app's until the layer says otherwise. The ring and the
            // backlight stay: the bridge never lights them, so it could not bring them back.
            if let pad, pad.isHeld || visited, !flushing {
                flushing = true
                do { try pad.slotsOff(timeout: 2) } catch { log("could not turn the key lights off first: \(error.description)") }
                flushing = false
            }
        case .back:
            if before != nil, before != .front {
                log("the bridge has the pad back: it lights the keys and acts on them again")
            } else {
                log("\(world.frontApp() ?? "another app") is in front: the bridge lights the keys and acts on them again")
            }
            activity()
            dirty = true
            flush()
        }
        updateHold()
    }

    /// Holds the pad through MicroBridge Helper while that keeps an app in `stepAsideFor` from
    /// acting on presses meant for the bridge, and shares it the rest of the time.
    private func updateHold() {
        guard let pad, pad.canHold, !flushing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let running = world.runningApps()
        let want = sharing.wantsHold(running: running, layer: padStatus?.layer, typedAt: typedAt, now: now)
        guard want != pad.isHeld, !want || now >= holdRetryAt else { return }
        // One conversation with the pad at a time.
        flushing = true
        defer { flushing = false }
        do {
            try pad.hold(want)
            holdProblem = nil
            log(want ? "holding the pad through MicroBridge Helper: other apps hear nothing from it"
                : "sharing the pad with other apps again")
        } catch {
            holdRetryAt = now + 30
            if holdProblem != error.description {
                holdProblem = error.description
                log(error.description)
            }
        }
    }

    /// The pad sent a report as a keyboard or mouse would. While it is held macOS does not get
    /// those, so share it at once for the next ones, and look at the layer.
    private func padTyped() {
        typedAt = ProcessInfo.processInfo.systemUptime
        guard pad?.isHeld == true else { return }
        // Not from inside the pad's own callback.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pad?.isHeld == true else { return }
                self.log("the pad typed as a keyboard or mouse while held, and macOS did not get it: sharing the pad")
                self.updateHold()
                self.checkLayer()
            }
        }
    }

    /// Another app's request was answered. A light write gets the bridge's lights painted back
    /// over it, unless the bridge is leaving the pad to that app.
    private func otherAppAnswered(_ method: String?) {
        guard let wait = sharing.otherReply(method: method, at: ProcessInfo.processInfo.systemUptime) else { return }
        // Not from inside the pad's own callback.
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sharing.repainting(at: ProcessInfo.processInfo.systemUptime)
                guard self.sharing.asideFor == nil else { return }
                if self.otherPaintLogged.map({ Date().timeIntervalSince($0) > 600 }) ?? true {
                    self.otherPaintLogged = Date()
                    self.log("another app wrote the lights (\(method ?? "?")): the bridge paints its own back. "
                        + "Said at most once every 10 minutes")
                }
                self.dirty = true
                self.flush()
            }
        }
    }

    /// Keys shown dark for a moment.
    private var blinked: Set<Int> = []

    /// The key goes dark and comes back, `times` over.
    private func blink(_ slot: Int, times: Int) {
        for step in 0 ..< times * 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(step)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if step % 2 == 0 { self.blinked.insert(slot) } else { self.blinked.remove(slot) }
                    self.dirty = true
                    self.flush()
                }
            }
        }
    }

    /// Keys shown red for a moment: a hold that could take no chat.
    private var flashed: Set<Int> = []

    /// The key shows red and goes back, twice: the pad's way to say no on a key that is dark.
    private func flash(_ slot: Int) {
        for step in 0 ..< 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(step)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if step % 2 == 0 { self.flashed.insert(slot) } else { self.flashed.remove(slot) }
                    self.dirty = true
                    self.flush()
                }
            }
        }
    }

    /// Says in the log when an Agent Key went from an idle session to one that needs its person.
    private func noteHandovers() {
        for note in state.takeNotes() { log(note) }
        for note in orca.takeNotes() { log(note) }
        for handover in state.takeHandovers() {
            // "The key pressed last" meant the session that just left it.
            if selected == handover.slot { selected = nil }
        }
    }

    /// Paints the pad from `state`. Socket commands can arrive while a write is waiting for
    /// the pad's answer; they mark `dirty` and this loop picks them up.
    private func flush() {
        noteHandovers()
        guard !flushing, let pad, sharing.asideFor == nil else { return }
        if let retryAt, Date() < retryAt { return }
        flushing = true
        defer { flushing = false }
        while dirty {
            dirty = false
            if let slot = selected, state.owner(of: slot) == nil { selected = nil }
            let pulses = state.slots(showing: shown)
            if pulses != pulsing {
                pulsing = pulses
                log(pulses.isEmpty ? "no key pulses: the session on screen has no key"
                    : "key \(pulses.sorted().map { String($0 + 1) }.joined(separator: ", ")) pulses: its session is on screen")
            }
            do {
                // Every layer of the bridge's own has its own six keys: the first shows Claude's
                // sessions, Orca's shows its chats, and any other has no agents.
                var lights: [SlotLight]
                if actingLayer == LayerWatch.ours {
                    lights = state.lights(config.lighting, selected: pulses, dimmed: dark)
                } else if actingLayer == orcaLayer {
                    lights = orca.lights(config.lighting, dimmed: dark)
                } else {
                    lights = (0 ..< BridgeState.slotCount).map { AgentStatus.off.light(slot: $0) }
                }
                for slot in blinked where lights.indices.contains(slot) { lights[slot] = AgentStatus.off.light(slot: slot) }
                if !dark {
                    for slot in flashed where lights.indices.contains(slot) {
                        lights[slot] = AgentStatus.failed.light(slot: slot, brightness: config.lighting.brightness,
                                                                color: config.lighting.color(.failed))
                    }
                }
                try pad.setSlots(lights, timeout: 2)
                if unanswered > 0 {
                    log("pad is answering again")
                    unanswered = 0
                    retryAt = nil
                }
                if refused {
                    refused = false
                    retryAt = nil
                    if lockStart != nil {
                        // That write was the dark one. The Mac is unlocked: show the keys.
                        lockStart = nil
                        lockAskedAt = nil
                        activity()
                        dirty = true
                    }
                    log("macOS takes writes to the pad again: the keys show their sessions")
                }
            } catch {
                dirty = true
                if case .writesRefused = error {
                    // Seen on 2026-11-21 while the Mac was locked. Reopening the pad changes
                    // nothing: dropping it each time reopened it every second. Keep it open,
                    // leave the lights as they are and try again until macOS lets writes through.
                    if !refused {
                        refused = true
                        log("macOS refuses writes to the pad, as it does while the Mac is locked. "
                            + "The lights stay as they are until it lets them through.")
                    }
                    retryAt = Date().addingTimeInterval(2)
                    return
                }
                if case .timeout = error {
                    // The pad takes commands over USB but says nothing back. Seen for hours on
                    // 2026-11-11 until the cable was replugged; Bluetooth mode with the cable in
                    // does the same. Reopening it changes nothing, so keep it open (its keys
                    // still arrive once it is back) and try again later.
                    unanswered += 1
                    if unanswered == 1 {
                        log("pad is not answering. Unplug its cable and plug it back in. Blue lights mean "
                            + "Bluetooth mode: hold its touch sensor 3 s, then tap until the lights turn white. "
                            + "Trying again quietly.")
                    }
                    retryAt = Date().addingTimeInterval(min(60, 5 * pow(2, Double(min(unanswered - 1, 6)))))
                    return
                }
                if self.pad === pad { drop("write failed: \(error.description)") }
                return
            }
        }
    }

    // MARK: Sessions across a restart

    /// Sessions and their keys as last written to disk.
    private var savedState: BridgeState?

    /// Writes the sessions and their keys to disk when they have changed, so a restart of the
    /// bridge keeps every key on its session.
    private func saveSessions() {
        saveOrcaKeys()
        guard state != savedState else { return }
        let path = world.sessions
        do {
            try state.snapshot().write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            savedState = state
        } catch {
            log("could not write \(path): \(error.localizedDescription)")
        }
    }

    /// Takes the sessions and their keys back from disk. A session whose process is gone, or
    /// whose pid now belongs to a newer process, counts as ended.
    private func restoreSessions() {
        guard let text = try? String(contentsOfFile: world.sessions, encoding: .utf8) else { return }
        let held = state.restore(text) { pid, saved in
            guard ProcessTree.isAlive(pid), let started = ProcessTree.started(pid) else { return false }
            return started <= saved.timeIntervalSince1970
        }
        _ = state.prune(isAlive: ProcessTree.isAlive)
        let live = state.sessions.values.filter { $0.slot != nil && $0.ended == nil }.count
        let kept = state.sessions.values.filter { $0.slot != nil }.count
        log("sessions from before the restart: \(kept) keep their keys (\(live) running, \(kept - live) ended), of \(held) on file")
        for note in state.takeNotes() { log(note) }
        savedState = state
        dirty = true
    }

    /// The keys of Orca's layer as last written to disk.
    private var savedOrca = OrcaKeys()

    /// Writes the chats on Orca's keys to disk when they have changed. They are there by hand,
    /// so a restart of the bridge or of Orca must not lose them.
    private func saveOrcaKeys() {
        guard orca != savedOrca else { return }
        let path = world.orcaKeys
        do {
            try orca.snapshot().write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            savedOrca = orca
        } catch {
            log("could not write \(path): \(error.localizedDescription)")
        }
    }

    /// Takes the chats on Orca's keys back from disk. A chat whose process is gone shows as
    /// closed until it reports again, or until a tap finds its tab open in Orca. Tests call it
    /// by hand.
    func restoreOrcaKeys() {
        guard let text = try? String(contentsOfFile: world.orcaKeys, encoding: .utf8) else { return }
        let held = orca.restore(text) { pid, saved in
            guard ProcessTree.isAlive(pid), let started = ProcessTree.started(pid) else { return false }
            return started <= saved.timeIntervalSince1970
        }
        savedOrca = orca
        guard held > 0 else { return }
        log("Orca chats from before the restart: \(held) keep their keys, \(orca.dimSlots.count) of them closed")
        dirty = true
    }

    // MARK: Orca's layer

    /// The layer whose six keys hold Orca's chats: the one `layerApps` gives Orca, when that
    /// is not the first. The first layer's keys are Claude's sessions' (D-053).
    private var orcaLayer: Int? {
        guard let layer = config.layer(ofApp: Orca.bundleID), layer != LayerWatch.ours else { return nil }
        return layer
    }

    private static func short(_ id: String) -> Substring { id.prefix(8) }

    /// What a chat in Orca said goes to the keys of Orca's layer, never to a key of Claude's
    /// (D-053). True when the command was about such a chat.
    private func orcaHeard(_ command: Command) -> Bool {
        switch command {
        case let .report(_, status, pid, cwd, host, transcript):
            guard let id = host?.orcaChat else { return false }
            guard orcaLayer != nil else {
                if !saidNoOrcaLayer {
                    saidNoOrcaLayer = true
                    log("a chat in Orca reported, but no layer is Orca's (layerApps): it gets no key. Said once")
                }
                return true
            }
            if status == .off {
                chatExited(id)
            } else if orca.report(id, status, pid: pid, cwd: cwd, transcript: transcript) {
                lightsChanged()
            }
            return true
        case let .end(id):
            guard orca.chats[id] != nil else { return false }
            chatExited(id)
            return true
        case let .forget(id):
            guard let chat = orca.chats[id] else { return false }
            if let slot = chat.slot { freeOrcaKey(slot) }
            orca.forget(id)
            return true
        default:
            return false
        }
    }

    /// A chat's process is gone: its tab was closed, or Orca stopped. Orca says which, a
    /// moment later, since it drops a closed tab a moment after its process. A closed chat
    /// stays on its key, dim (D-054).
    private func chatExited(_ id: String) {
        guard orca.exited(id), let slot = orca.chats[id]?.slot else { return }
        dirty = true
        let heard = orca.chats[id]?.heard
        let ask: @MainActor () -> Void = { [weak self] in
            self?.world.orca.place(id) { [weak self] result in
                // A chat that reported since is running again.
                guard let self, let chat = self.orca.chats[id], chat.slot == slot, chat.ended == nil, chat.heard == heard else { return }
                switch result {
                case .success(.some):
                    self.log("chat \(Self.short(id))'s process ended, but Orca still has its tab: key \(slot + 1) stays lit")
                case .success(nil):
                    if self.orca.end(id) { self.lightsChanged() }
                case let .failure(problem):
                    self.log("could not ask Orca whether chat \(Self.short(id)) is still open (\(problem.text)): key \(slot + 1) counts it as closed")
                    if self.orca.end(id) { self.lightsChanged() }
                }
                self.saveOrcaKeys()
                self.flush()
            }
        }
        let wait = world.orca.settle
        if wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { MainActor.assumeIsolated { ask() } }
        } else {
            ask()
        }
    }

    /// Orca's open Claude chats, as the answer to `orca.chats`, for the window and the panel
    /// to choose from. Titles pass through: they are kept in memory for the chats on keys, and
    /// never in the log or on file.
    func orcaChats(done: @escaping @MainActor (String) -> Void) {
        world.orca.chats { [weak self] result in
            switch result {
            case let .success(chats):
                self?.orca.learn(titles: Dictionary(chats.map { ($0.id, $0.title) }) { first, _ in first })
                done(Reply.orcaChats(chats))
            case let .failure(problem): done(Reply.error(problem.text))
            }
        }
    }

    /// A key of Orca's layer by socket command: `orca.take` as a hold on an empty key,
    /// `orca.free` as a hold on a taken one, `orca.show` as a tap's jump. `done` hears nil, or
    /// why it did not happen.
    func orcaCommand(_ command: Command, done: @escaping @MainActor (String?) -> Void) {
        guard orcaLayer != nil else {
            done(#"no layer is Orca's: give it one in the config, such as "layerApps": {"2": ["orca"]}"#)
            return
        }
        switch command {
        case let .orcaTake(slot, chat):
            if orca.owner(of: slot) != nil {
                done("key \(slot + 1) holds a chat already: free it first")
            } else if let chat {
                world.orca.place(chat) { [weak self] result in
                    guard let self else { return }
                    var problem: String?
                    switch result {
                    case let .success(place?): problem = self.put(place, on: slot)
                    case .success(nil): problem = "Orca has no open Claude chat with that ID"
                    case let .failure(failed): problem = failed.text
                    }
                    done(problem)
                    self.flush()
                }
            } else {
                takeChatOnScreen(slot, done: done)
            }
        case let .orcaFree(slot):
            done(freeOrcaKey(slot) ? nil : "key \(slot + 1) holds no chat")
        case let .orcaShow(slot):
            guard let chat = orca.owner(of: slot) else {
                done("key \(slot + 1) holds no chat")
                return
            }
            showChat(chat.id, slot: slot, done: done)
        default:
            done("not a command for Orca's keys")
        }
    }

    /// A key of Orca's layer was tapped or held. The keys are filled by hand (D-043): a hold on
    /// an empty key takes the chat on screen in Orca, a hold on a taken key frees it, and a
    /// tap does what `agentKeys.press` says with the key's chat.
    private func orcaKey(_ slot: Int, _ trigger: String, layer: Int) {
        let key = "key \(slot + 1) on layer \(layer)"
        switch trigger {
        case "hold":
            if orca.owner(of: slot) != nil {
                log("AG.hold \(key): the key lets its chat go")
                freeOrcaKey(slot)
            } else {
                log("AG.hold \(key): the key takes the chat on screen in Orca")
                takeChatOnScreen(slot) { _ in }
            }
        case "press":
            guard let chat = orca.owner(of: slot) else {
                log("AG.press \(key): no chat on this key. Hold it to take the chat on screen in Orca")
                return
            }
            orcaTap(chat, slot: slot, layer: layer)
        default:
            break
        }
    }

    /// Puts the chat on screen in Orca on that empty key. Orca's window says which tab shows,
    /// and Orca's command line which chats there are. When that does not single one out the
    /// key flashes red and the log says why.
    private func takeChatOnScreen(_ slot: Int, done: @escaping @MainActor (String?) -> Void) {
        // The window as it is at the hold, not when Orca has answered.
        let tabs = world.orca.tabs()
        world.orca.chats { [weak self] result in
            guard let self else { return }
            var problem: String?
            switch result {
            case let .failure(failed):
                problem = failed.text
            case let .success(chats):
                switch Orca.pick(tabs: tabs, chats: chats) {
                case let .unclear(why): problem = why
                case let .chat(chat): problem = self.put(chat, on: slot)
                }
            }
            if let problem {
                self.log("key \(slot + 1) takes no chat: \(problem)")
                self.flash(slot)
            }
            done(problem)
            self.flush()
        }
    }

    /// Nil when the key holds the chat now, or why it does not.
    private func put(_ chat: OrcaChat, on slot: Int) -> String? {
        if let other = orca.chats[chat.id]?.slot { return "that chat is on key \(other + 1) already" }
        guard orca.take(slot: slot, chat: chat.id, status: chat.status, title: chat.title) else {
            return "key \(slot + 1) holds a chat already"
        }
        lightsChanged()
        saveOrcaKeys()
        return nil
    }

    @discardableResult
    private func freeOrcaKey(_ slot: Int) -> Bool {
        guard orca.free(slot: slot) != nil else { return false }
        lightsChanged()
        saveOrcaKeys()
        return true
    }

    /// A tap on a key that holds a chat. A closed chat's key ignores taps (D-054), unless Orca
    /// has its tab open again, as after a restart of Orca.
    private func orcaTap(_ chat: Session, slot: Int, layer: Int) {
        let key = "key \(slot + 1) on layer \(layer)"
        if chat.ended != nil {
            world.orca.place(chat.id) { [weak self] result in
                guard let self, let now = self.orca.owner(of: slot), now.id == chat.id, now.ended != nil else { return }
                guard case let .success(place?) = result else {
                    self.log("AG.press \(key): its chat is closed, the tap does nothing. Hold the key to free it")
                    return
                }
                self.orca.reopen(chat.id)
                self.lightsChanged()
                self.saveOrcaKeys()
                if let open = self.orca.owner(of: slot) { self.orcaTap(open, slot: slot, layer: layer, place: place) }
                self.flush()
            }
            return
        }
        orcaTap(chat, slot: slot, layer: layer, place: nil)
    }

    private func orcaTap(_ chat: Session, slot: Int, layer: Int, place: OrcaChat?) {
        let app = world.frontApp()
        let actions = config.actions(for: "AG", "press", app: app)
        log("AG.press key \(slot + 1) on layer \(layer) in \(app ?? "no app"): " + actions.map(\.description).joined(separator: ", "))
        list: for action in actions {
            switch action {
            case .none, .pin, .pointerToChat, .lock:
                // Nothing to pin: the key keeps its chat until it is freed. The pointer and
                // the lock are the first layer's.
                break
            case .ack:
                if orca.acknowledge(slot: slot) { dirty = true }
            case .forget:
                freeOrcaKey(slot)
                break list
            case .jump, .focus:
                showChat(chat.id, slot: slot, place: place) { _ in }
            default:
                if runner.run(action, slot: slot, session: chat) { break list }
            }
        }
    }

    /// Brings the key's chat on screen in Orca. Orca says where the chat is open; with no tab
    /// for it the chat is closed, and its key goes dim.
    private func showChat(_ id: String, slot: Int, place known: OrcaChat? = nil, done: @escaping @MainActor (String?) -> Void) {
        let show: @MainActor (OrcaChat) -> Void = { [weak self] place in
            guard let self else { return }
            self.world.orca.show(place) { [weak self] note in
                self?.log("key \(slot + 1): chat \(Self.short(id)): \(note)")
                done(nil)
            }
        }
        if let known {
            show(known)
            return
        }
        world.orca.place(id) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(place?):
                show(place)
            case .success(nil):
                if self.orca.end(id) { self.lightsChanged() }
                self.saveOrcaKeys()
                self.log("key \(slot + 1): Orca has no open tab for chat \(Self.short(id)): nothing to show")
                done("its chat is closed")
            case let .failure(problem):
                self.log("key \(slot + 1): could not ask Orca where chat \(Self.short(id)) is: \(problem.text)")
                done(problem.text)
            }
            self.flush()
        }
    }

    // MARK: The session on screen

    /// Asks the Claude app which sessions its windows show, so their Agent Keys can pulse.
    private func checkShown() {
        var now: [SessionHost] = []
        if config.lighting.pulseSelected, pad != nil, !dark, sharing.asideFor == nil {
            // Asking takes the main thread for a moment: it would stutter a press or a scroll.
            if gestures.hasKeysDown || scrollTimer != nil { return }
            if let askShownAfter, Date() < askShownAfter { return }
            let started = Date()
            for bundle in config.apps["claude"] ?? [] {
                now += ScreenButtons.shownSessions(bundleID: bundle)
            }
            let took = Date().timeIntervalSince(started)
            if took > 0.3 {
                // The app is busy or hung. Asking every second would hold up the keys.
                askShownAfter = Date().addingTimeInterval(10)
                log(String(format: "asking the Claude app what is on screen took %.1f s; asking again in 10 s", took))
            }
        }
        guard now != shown else { return }
        shown = now
        state.onScreen = now
        dirty = true
        log("on screen: " + (now.isEmpty ? "no session" : now.map(\.description).joined(separator: ", ")))
    }

    // MARK: Layer

    /// The layer the bridge acts on now: the pad's, while that is one of the bridge's own
    /// (`layerApps`), and the first one on any other layer or before the pad has said.
    private var actingLayer: Int {
        guard let layer = padStatus?.layer, config.ownLayers.contains(layer) else { return LayerWatch.ours }
        return layer
    }

    /// The layer `app` belongs to, when that is one of the bridge's own and not the one it
    /// acts on now. Then the pad's controls do nothing in that app: the layer says which app
    /// the pad is for.
    private func otherLayer(of app: String?) -> Int? {
        guard let app, let its = config.layer(ofApp: app), its != actingLayer else { return nil }
        return its
    }

    /// Notes the layer the bridge acts on, and returns it when it changed. Then a push or a
    /// hold begun on the other layer ends, and the keys are painted for this one.
    private func layerActedOn() -> Int? {
        let now = actingLayer
        guard now != actedLayer else { return nil }
        actedLayer = now
        stopScrolling(why: "the pad changed layer")
        gestures = Gestures()
        holdTimer?.invalidate()
        holdTimer = nil
        dirty = true
        return now
    }

    /// Asks the pad which layer it is on. A tap on its touch sensor changes the layer without a
    /// word, and on every layer but the first its keys send this bridge nothing.
    private func checkLayer() {
        guard !flushing, unanswered == 0, !refused, !gestures.hasKeysDown, let pad else { return }
        // One conversation with the pad at a time: light writes wait for this answer.
        flushing = true
        let status: DeviceStatus
        do {
            status = try pad.status(timeout: 2)
            flushing = false
        } catch {
            flushing = false
            // No answer: let the light write notice and back off.
            if case .timeout = error, self.pad === pad {
                dirty = true
                flush()
            }
            return
        }
        guard self.pad === pad else { return }
        padStatus = status
        let acting = layerActedOn()
        let before = sharing.reason
        let read = sharing.layer(status.layer, running: world.runningApps())
        if let pass = read.pass { passed(pass) }
        if let change = read.change { sharingChanged(change, before: before) }
        if let low = battery.read(battery: status.battery, charging: status.charging) {
            log("pad battery is at \(low)% and it is not charging")
            notify(title: "Codex Micro battery is at \(low)%", text: "Plug it in to charge.")
        }
        let from = layers.layer
        let seen = layers.read(status.layer)
        if let now = acting, status.layer == now, sharing.asideFor == nil {
            let apps = config.apps(onLayer: now)
            log("the pad is on layer \(now), one of the bridge's own: its keys and controls are for "
                + (apps.isEmpty ? "no app in particular" : apps.joined(separator: ", ")))
            // The first reading of a pad is where it starts, and `passed` has had its say.
            if config.layerWarning, from != nil, read.pass == nil {
                var names: [String] = []
                for name in (config.layerApps[now] ?? []).map({ world.appName(config.apps[$0]?.first ?? $0) })
                    where !names.contains(name) { names.append(name) }
                notify(title: "Codex Micro is on layer \(now)",
                       text: names.isEmpty ? "MicroBridge acts on its keys." : "Its keys are for \(names.joined(separator: " and ")).")
            }
        }
        switch seen {
        case let .away(layer) where sharing.hasKeys(on: layer):
            // No mishap: the pad's keys work on that layer, and `passed` said whose they are.
            break
        case .away where read.pass != nil && !sharing.layerKeys:
            // A visit, and `passed` said what it did.
            break
        case let .away(layer):
            log("pad is on layer \(layer), where its keys do not reach this bridge. "
                + "Tap its touch sensor (bottom-left edge) to return to layer \(LayerWatch.ours).")
            if config.layerWarning {
                notify(title: "Codex Micro is on layer \(layer)",
                       text: "Its keys are off. Tap the touch sensor (bottom-left edge) to return to layer \(LayerWatch.ours).")
            }
        case .back where from.map(sharing.hasKeys(on:)) == true:
            // It comes from a layer where its keys worked as well, and `passed` said who
            // has them now.
            dirty = true
        case .back:
            let other = sharing.handed?.app
            log("pad is back on layer \(LayerWatch.ours)" + (other.map { ": \($0) has its keys" } ?? ""))
            if config.layerWarning {
                notify(title: "Codex Micro is back on layer \(LayerWatch.ours)",
                       text: other.map { "\(world.appName($0)) has its keys." } ?? "Its keys work again.")
            }
            dirty = true
        case nil:
            break
        }
        flush()
        updateHold()
        if case .away = seen { readOften() }
    }

    /// Says what a visit to a layer, the layer the pad is on, or an app that quit, did about
    /// who has the pad.
    private func passed(_ pass: PadSharing.Pass) {
        // With the pad's keys on its layers nothing is left to tap: the layer says it all.
        let stays = sharing.layerKeys
        let back = "Tap the touch sensor again to go back to layer \(LayerWatch.ours)"
        let title: String
        let text: String
        switch pass {
        case let .handed(app, layer):
            // `sharingChanged` writes this one to the log.
            title = "\(world.appName(app)) has the pad"
            text = stays ? "The pad is on layer \(layer)." : "\(back), where its keys are."
        case let .tookBack(app, layer) where stays:
            log("the pad left layer \(layer): the bridge takes it back from \(app)")
            title = "MicroBridge has the pad"
            text = padStatus?.layer.map { "The pad is on layer \($0)." } ?? "The pad left layer \(layer)."
        case let .tookBack(app, layer):
            log("a second visit to layer \(layer) takes the pad back from \(app)")
            title = "MicroBridge has the pad"
            text = "\(back), where its keys are."
        case let .notOpen(app, layer) where stays:
            log("the pad is on layer \(layer), which is \(app)'s, but it is not open: the bridge keeps the pad")
            title = "\(world.appName(app)) is not open"
            text = "MicroBridge keeps the pad on layer \(layer)."
        case let .notOpen(app, layer):
            log("a visit to layer \(layer) passes the pad to \(app), but it is not open: the bridge keeps the pad")
            title = "\(world.appName(app)) is not open"
            text = "MicroBridge keeps the pad. \(back)."
        case let .quit(app):
            log("\(app) quit while it had the pad: the bridge takes it back")
            title = "MicroBridge has the pad"
            text = "\(world.appName(app)) quit."
        }
        if config.layerWarning { notify(title: title, text: text) }
    }

    /// How often, and how many times, the layer is read while a tap back is due: 10 s in all.
    static let quickGap: TimeInterval = 0.2
    static let quickReads = 50

    /// The pad just left its first layer, where it would be held. The tap back comes soon, and
    /// the first press after it must find the pad held again, so the reading of every second
    /// is too slow. Reads the layer five times a second until the pad is back, 10 s at most.
    private func readOften() {
        quickLayer?.invalidate()
        quickLayer = nil
        guard steadyLayer == nil, !config.layers.isEmpty, let pad, pad.canHold,
              sharing.holdsOnFirstLayer(running: world.runningApps()) else { return }
        quickReadsLeft = Self.quickReads
        quickLayer = Timer.scheduledTimer(withTimeInterval: Self.quickGap, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.quickRead() }
        }
    }

    private func quickRead() {
        quickReadsLeft -= 1
        guard quickReadsLeft >= 0, pad != nil, padStatus?.layer != LayerWatch.ours else {
            quickLayer?.invalidate()
            quickLayer = nil
            return
        }
        checkLayer()
    }

    /// How often the layer is read while one tap can change who has the pad.
    static let steadyGap: TimeInterval = 0.25

    /// With the pad's keys on its layers (`layerKeys`) one tap changes who has the pad, and the
    /// pad says nothing when it happens. So while an app with a layer is open the layer is read
    /// four times a second: the first press after a tap must go to the right app.
    private func watchLayer() {
        let want = pad != nil && sharing.watchesLayer(running: world.runningApps())
        guard want != (steadyLayer != nil) else { return }
        steadyLayer?.invalidate()
        steadyLayer = nil
        guard want else { return }
        quickLayer?.invalidate()
        quickLayer = nil
        steadyLayer = Timer.scheduledTimer(withTimeInterval: Self.steadyGap, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLayer() }
        }
    }

    private func notify(title: String, text: String) { world.notify(title, text) }

    /// A macOS notification through `osascript`, so the bridge needs no permission of its own.
    static func notification(title: String, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
                             "-e", "end run", title, text]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// The name of the app with that bundle id as the Finder shows it, or the id itself.
    static func name(ofApp id: String) -> String {
        if let name = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id })?.localizedName {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
