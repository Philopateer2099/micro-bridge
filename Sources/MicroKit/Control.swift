import Foundation

/// The daemon's socket protocol: one JSON object per line in, one per line out.
///
///     {"op":"report","session":"abc","status":"working","pid":123,"cwd":"/x"}  → {"ok":true}
///     {"op":"end","session":"abc"}               → {"ok":true}        (its process is over; it may keep its key)
///     {"op":"forget","session":"abc"}            → {"ok":true}        (drop it and free its key)
///     {"op":"pin","session":"abc","slot":2}      → {"ok":true}        (it keeps that key; "slot" is optional)
///     {"op":"unpin","session":"abc"}             → {"ok":true}
///     {"op":"set","slot":0,"status":"working"}   → {"ok":true}        (paint a slot by hand)
///     {"op":"clear"}                             → {"ok":true}        (forget everything)
///     {"op":"state"}                             → {"ok":true,"connected":…,"slots":[…],"sessions":[…],"layer":…,"battery":…}
///     {"op":"subscribe"}                         → {"ok":true}, then one event object per line
///     {"op":"orca.take","slot":2}                → {"ok":true}        (the key takes the chat on screen in Orca)
///     {"op":"orca.take","slot":2,"session":"…"}  → {"ok":true}        (the key takes that chat, by Orca's session ID)
///     {"op":"orca.free","slot":2}                → {"ok":true}
///     {"op":"orca.show","slot":2}                → {"ok":true}        (as a tap on that key of Orca's layer)
///     {"op":"orca.chats"}                        → {"ok":true,"chats":[{"session":"…","title":"…","status":"done","worktree":"…"}]}
///     {"op":"commands","target":"orca"}          → {"ok":true,"commands":[{"name":"APPR","title":"Approve","controls":["Key 8"],"here":{"press":["…"]},"elsewhere":{"press":["…"]}}]}
///     {"op":"command.set","name":"APPR","target":"orca","actions":["…"]}  → {"ok":true}  (written to the config file; "trigger" is optional)
///
/// `report` is how agents show up: the daemon gives each session its own Agent Key. It may
/// carry `"host":"claude:local_…"`, which is where a jump goes. With `"host":"orca:<id>"` the
/// session is a chat in Orca: it belongs to Orca's layer, whose keys are filled by hand.
public enum Command: Sendable, Equatable {
    case report(session: String, status: AgentStatus, pid: Int?, cwd: String?, host: SessionHost? = nil,
                transcript: String? = nil)
    case end(session: String)
    case forget(session: String)
    /// The session keeps a key until it is unpinned or forgotten: `slot`, or with nil the key
    /// it has, or failing that the key of the holder that would give up first.
    case pin(session: String, slot: Int? = nil)
    case unpin(session: String)
    case set(slot: Int, status: AgentStatus)
    case clear
    case state
    case subscribe
    /// A key of Orca's layer takes a chat: the one named by Orca's session ID, or with nil
    /// the chat on screen in Orca, as a hold on the empty key does.
    case orcaTake(slot: Int, chat: String? = nil)
    /// That key of Orca's layer lets its chat go.
    case orcaFree(slot: Int)
    /// As a tap on that key of Orca's layer: its chat comes on screen.
    case orcaShow(slot: Int)
    /// Asks which Claude chats are open in Orca, for the screens that put them on keys.
    case orcaChats
    /// Asks what the commands do in one target (an app group, a bundle id or "default"), for
    /// the panel in Orca.
    case commands(target: String)
    /// Sets what a command does on one trigger in one target, in the config file. No actions
    /// removes that part.
    case commandSet(name: String, target: String, trigger: String = "press", actions: [String])

    public struct Invalid: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ line: String) throws(Invalid) -> Command {
        guard let value = JSONValue.parse(line), let op = value["op"]?.string else {
            throw Invalid(description: "expected a JSON object with \"op\"")
        }
        func status() throws(Invalid) -> AgentStatus {
            guard let name = value["status"]?.string, let status = AgentStatus(rawValue: name) else {
                let names = AgentStatus.allCases.map(\.rawValue).joined(separator: ", ")
                throw Invalid(description: "\"status\" must be one of: \(names)")
            }
            return status
        }
        func session() throws(Invalid) -> String {
            guard let id = value["session"]?.string, !id.isEmpty, id.utf8.count <= 128 else {
                throw Invalid(description: "\"session\" must be a string of 1 to 128 bytes")
            }
            return id
        }
        func target() throws(Invalid) -> String {
            guard let target = value["target"]?.string, !target.isEmpty, target.utf8.count <= 128,
                  target.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F }) else {
                throw Invalid(description: "\"target\" must be an app group, a bundle id or \"default\"")
            }
            return target
        }
        switch op {
        case "commands": return .commands(target: try target())
        case "command.set":
            guard let name = value["name"]?.string?.uppercased(), (1 ... 24).contains(name.count),
                  name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-_".contains($0)) }) else {
                throw Invalid(description: "\"name\" must be a command's name")
            }
            let trigger = value["trigger"]?.string ?? "press"
            guard Config.triggers.contains(trigger) else {
                throw Invalid(description: "\"trigger\" must be one of: " + Config.triggers.joined(separator: ", "))
            }
            guard case let .array(items)? = value["actions"], items.count <= 32,
                  items.allSatisfy({ ($0.string?.utf8.count ?? 4096) <= 2048 }) else {
                throw Invalid(description: "\"actions\" must be a list of at most 32 actions")
            }
            return .commandSet(name: name, target: try target(), trigger: trigger, actions: items.compactMap(\.string))
        case "report":
            let pid = value["pid"]?.int
            if let pid, pid <= 1 { throw Invalid(description: "\"pid\" must be greater than 1") }
            var host: SessionHost?
            if let text = value["host"]?.string {
                guard let parsed = SessionHost(text) else {
                    throw Invalid(description: "\"host\" must be claude:local_<id> or orca:<id>")
                }
                host = parsed
            }
            let transcript = value["transcript"]?.string
            if let transcript, !transcript.hasPrefix("/") || transcript.utf8.count > 2048 {
                throw Invalid(description: "\"transcript\" must be an absolute path of at most 2048 bytes")
            }
            return .report(session: try session(), status: try status(), pid: pid, cwd: value["cwd"]?.string,
                           host: host, transcript: transcript)
        case "end":
            return .end(session: try session())
        case "forget":
            return .forget(session: try session())
        case "pin":
            guard let wanted = value["slot"], wanted != .null else { return .pin(session: try session()) }
            guard let slot = wanted.int, (0 ..< BridgeState.slotCount).contains(slot) else {
                throw Invalid(description: "\"slot\" must be 0 to \(BridgeState.slotCount - 1)")
            }
            return .pin(session: try session(), slot: slot)
        case "unpin":
            return .unpin(session: try session())
        case "set":
            guard let slot = value["slot"]?.int, (0 ..< BridgeState.slotCount).contains(slot) else {
                throw Invalid(description: "\"slot\" must be 0 to \(BridgeState.slotCount - 1)")
            }
            return .set(slot: slot, status: try status())
        case "clear": return .clear
        case "state": return .state
        case "subscribe": return .subscribe
        case "orca.chats": return .orcaChats
        case "orca.take", "orca.free", "orca.show":
            guard let slot = value["slot"]?.int, (0 ..< BridgeState.slotCount).contains(slot) else {
                throw Invalid(description: "\"slot\" must be 0 to \(BridgeState.slotCount - 1)")
            }
            if op == "orca.free" { return .orcaFree(slot: slot) }
            if op == "orca.show" { return .orcaShow(slot: slot) }
            guard let wanted = value["session"], wanted != .null else { return .orcaTake(slot: slot) }
            guard let id = wanted.string, SessionHost("orca:" + id) != nil else {
                throw Invalid(description: "\"session\" must be an Orca session ID")
            }
            return .orcaTake(slot: slot, chat: id)
        default: throw Invalid(description: "unknown op \"\(op)\"")
        }
    }
}

/// One agent session the daemon knows about.
public struct Session: Sendable, Equatable {
    public let id: String
    public var status: AgentStatus
    /// Its Agent Key, or nil while all six are taken.
    public var slot: Int?
    /// The agent's process, when known. A session whose process is gone has ended.
    public var pid: Int?
    public var cwd: String?
    /// Where to show it, when the agent said.
    public var host: SessionHost?
    /// The file Claude Code keeps the session's record in, when the agent said.
    public var transcript: String?
    /// When the agent last reported.
    public var heard: Date?
    /// When its process ended, for a session that keeps its key so a press can open it again.
    public var ended: Date?
    /// When its Agent Key was last pressed.
    public var pressed: Date?
    /// Pinned by its person: it keeps its key against more urgent sessions and after it ends,
    /// until it is unpinned or forgotten.
    public var pinned = false
    /// Order of the latest report; larger is newer.
    var seen: Int
}

/// Where a session can be shown, so an Agent Key can jump straight to it.
public enum SessionHost: Sendable, Equatable, CustomStringConvertible {
    /// A Code session in the Claude desktop app, by its `local_…` id.
    case claudeDesktop(String)
    /// A chat in Orca, by Orca's session ID. The chat keeps it across /clear.
    case orcaChat(String)

    /// Parses "claude:local_…" and "orca:…". The id later goes into a link or a command line,
    /// so only plain id characters pass.
    public init?(_ text: String) {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let id = String(text[text.index(after: colon)...])
        switch text[..<colon] {
        case "claude" where Self.isID(id, prefix: "local_", extra: "-"): self = .claudeDesktop(id)
        case "orca" where Self.isID(id, prefix: "", extra: "-_"): self = .orcaChat(id)
        default: return nil
        }
    }

    /// The session a page of the Claude app shows, from the page's address:
    /// "https://claude.ai/epitaxy/local_…". Nil for every other page.
    public init?(page: URL) {
        let parts = page.pathComponents
        guard let at = parts.firstIndex(of: "epitaxy"), parts.indices.contains(at + 1),
              let host = SessionHost("claude:" + parts[at + 1]) else { return nil }
        self = host
    }

    /// What an agent's own environment says about where it runs. A session of the Claude app
    /// says so with `CLAUDE_CODE_HOST_SESSION_ID`. A chat in Orca has `ORCA_AGENT_SESSION_ID`
    /// and no `ORCA_TERMINAL_HANDLE`, which Orca sets in its terminals only.
    public init?(environment: [String: String]) {
        if let id = environment["CLAUDE_CODE_HOST_SESSION_ID"] {
            guard let host = SessionHost("claude:" + id) else { return nil }
            self = host
            return
        }
        guard environment["ORCA_TERMINAL_HANDLE"]?.isEmpty != false, let id = environment["ORCA_AGENT_SESSION_ID"],
              let host = SessionHost("orca:" + id) else { return nil }
        self = host
    }

    /// Orca's session ID, when this is a chat in Orca.
    public var orcaChat: String? {
        if case let .orcaChat(id) = self { return id }
        return nil
    }

    public var description: String {
        switch self {
        case let .claudeDesktop(id): "claude:" + id
        case let .orcaChat(id): "orca:" + id
        }
    }

    private static func isID(_ id: String, prefix: String, extra: String) -> Bool {
        guard id.hasPrefix(prefix) else { return false }
        let rest = id.dropFirst(prefix.count).unicodeScalars
        return (1 ... 64).contains(rest.count) && rest.allSatisfy { scalar in
            ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar) || ("0" ... "9").contains(scalar)
                || extra.unicodeScalars.contains(scalar)
        }
    }
}

/// What the six Agent Keys should show, and which session owns each. The daemon repaints the
/// pad from this after every change and every reconnect.
public struct BridgeState: Sendable, Equatable {
    public static let slotCount = 6
    /// Sessions kept at most, counting those waiting for a key.
    static let maxSessions = 32

    public private(set) var slots = [AgentStatus](repeating: .off, count: slotCount)
    public private(set) var sessions: [String: Session] = [:]
    /// A free key held for the next session to show up, set when that key was pressed to start one.
    public private(set) var reserved: Int?
    /// When every key is taken, a session without one takes the key of a session that wants
    /// its person less. Off: only a session that ended gives its key up.
    public var urgentFirst = true {
        didSet { promote() }
    }
    /// The sessions the Claude app's windows show. Such a session keeps its key.
    public var onScreen: [SessionHost] = [] {
        didSet { if onScreen != oldValue { promote() } }
    }
    /// Seconds a session keeps its key for sure after that key was pressed, while the app
    /// brings it on screen.
    public static let pressedSeconds: Double = 5
    /// Seconds a session that ended keeps its Agent Key, so a press can open it again. Zero:
    /// the key goes dark as soon as the session ends.
    public var rememberSeconds: Double = .infinity {
        didSet {
            guard rememberSeconds <= 0 else { return }
            for session in sessions.values where session.ended != nil && !session.pinned { remove(session.id) }
        }
    }
    /// Keys that changed hands since `takeHandovers` was last called.
    private var handovers: [Handover] = []
    /// What happened to sessions and their keys since `takeNotes` was last called, for the log.
    private var notes: [String] = []
    private var clock = 0

    /// One Agent Key going from an idle session to a session that needs its person.
    public struct Handover: Sendable, Equatable {
        public let slot: Int
        public let from: String
        public let to: String

        public init(slot: Int, from: String, to: String) {
            self.slot = slot
            self.from = from
            self.to = to
        }
    }

    /// The handovers since the last call, oldest first.
    public mutating func takeHandovers() -> [Handover] {
        defer { handovers = [] }
        return handovers
    }

    /// What happened to sessions and their keys since the last call, oldest first.
    public mutating func takeNotes() -> [String] {
        defer { notes = [] }
        return notes
    }

    private static func short(_ id: String) -> String { String(id.prefix(8)) }

    public init() {}

    /// Applies a command. Returns true if the lights changed.
    @discardableResult
    public mutating func apply(_ command: Command, at now: Date = Date()) -> Bool {
        let before = slots
        switch command {
        case let .report(id, status, pid, cwd, host, transcript):
            if status == .off {
                end(id, at: now)
            } else {
                report(id, status, pid: pid, cwd: cwd, host: host, transcript: transcript, at: now)
            }
        case let .end(id): end(id, at: now)
        case let .forget(id):
            if let slot = sessions[id]?.slot { notes.append("session \(Self.short(id)) forgotten: key \(slot + 1) is free") }
            remove(id)
        case let .pin(id, slot): pin(id, to: slot, at: now)
        case let .unpin(id): unpin(id, at: now)
        case let .set(slot, status): slots[slot] = status
        case .clear:
            slots = [AgentStatus](repeating: .off, count: Self.slotCount)
            sessions = [:]
            reserved = nil
        case .state, .subscribe, .orcaTake, .orcaFree, .orcaShow, .orcaChats, .commands, .commandSet: break
        }
        return slots != before
    }

    /// Holds a free key for the next new session, or with nil lets it go again.
    public mutating func reserve(_ slot: Int?) {
        reserved = slot.flatMap { slots.indices.contains($0) && owner(of: $0) == nil ? $0 : nil }
    }

    /// Pins a session to a key. With no key named it stays on the key it has; one that waits
    /// takes a free key, or the key of the holder that would give up first among those not
    /// pinned. A session already on the named key trades places with it, or waits when the
    /// pinned one had no key to trade. False when there is no such session or no key for it.
    @discardableResult
    public mutating func pin(_ id: String, to wanted: Int? = nil, at now: Date = Date()) -> Bool {
        guard var session = sessions[id] else { return false }
        let from = session.slot
        let target: Int
        if let wanted {
            guard slots.indices.contains(wanted) else { return false }
            target = wanted
        } else if let from {
            target = from
        } else if let free = freeSlot() {
            target = free
        } else if let slot = sessions.values.filter({ $0.slot != nil && !$0.pinned }).min(by: Self.givesUpBefore)?.slot {
            target = slot
        } else {
            notes.append("session \(Self.short(id)) cannot be pinned: every key is pinned")
            return false
        }
        if from != target {
            if let other = owner(of: target) {
                if let from {
                    sessions[other.id]?.slot = from
                    slots[from] = other.status
                    notes.append("session \(Self.short(other.id)) moves to key \(from + 1)")
                } else if other.ended != nil {
                    sessions[other.id] = nil
                    notes.append("key \(target + 1) forgets session \(Self.short(other.id)), which ended")
                } else {
                    sessions[other.id]?.slot = nil
                    sessions[other.id]?.pinned = false
                    notes.append("session \(Self.short(other.id)) gives up key \(target + 1) and waits")
                }
            } else if let from {
                slots[from] = .off
            }
        }
        session.slot = target
        session.pinned = true
        sessions[id] = session
        slots[target] = session.status
        if reserved == target { reserved = nil }
        notes.append("session \(Self.short(id)) is pinned to key \(target + 1)")
        if let from, from != target, owner(of: from) == nil { fill(from) }
        promote(at: now)
        return true
    }

    /// Takes a session's pin away. It keeps its key until a more urgent session wants it.
    /// False when it was not pinned.
    @discardableResult
    public mutating func unpin(_ id: String, at now: Date = Date()) -> Bool {
        guard let session = sessions[id], session.pinned else { return false }
        sessions[id]?.pinned = false
        notes.append("session \(Self.short(id)) is no longer pinned" + (session.slot.map { " to key \($0 + 1)" } ?? ""))
        promote(at: now)
        return true
    }

    /// The keys whose sessions are pinned.
    public var pinnedSlots: Set<Int> {
        Set(sessions.values.compactMap { $0.pinned ? $0.slot : nil })
    }

    /// A press on an Agent Key marks a finished or failed session as seen.
    @discardableResult
    public mutating func acknowledge(slot: Int, at now: Date = Date()) -> Bool {
        guard slots.indices.contains(slot), slots[slot] == .done || slots[slot] == .failed else { return false }
        slots[slot] = .idle
        if let id = owner(of: slot)?.id { sessions[id]?.status = .idle }
        promote(at: now)
        return true
    }

    /// The person acted on the sessions shown in these places: what those had finished counts
    /// as read. Returns the keys that changed.
    @discardableResult
    public mutating func acknowledge(showing hosts: [SessionHost], at now: Date = Date()) -> [Int] {
        slots(showing: hosts).sorted().filter { acknowledge(slot: $0, at: now) }
    }

    /// The Agent Key was pressed: its session keeps the key for a moment.
    public mutating func touch(slot: Int, at now: Date = Date()) {
        if let id = owner(of: slot)?.id { sessions[id]?.pressed = now }
    }

    /// Settles who holds the keys. Call it now and then: a pressed key's hold on its session
    /// runs out by itself. Returns true if the lights changed.
    @discardableResult
    public mutating func rebalance(at now: Date = Date()) -> Bool {
        let before = slots
        promote(at: now)
        return slots != before
    }

    /// Forgets sessions whose process is gone. Returns true if the lights changed.
    @discardableResult
    public mutating func prune(isAlive: (Int) -> Bool, at now: Date = Date()) -> Bool {
        let before = slots
        for session in sessions.values {
            if let pid = session.pid, !isAlive(pid) {
                end(session.id, at: now)
            } else if !session.pinned, let ended = session.ended, now.timeIntervalSince(ended) >= rememberSeconds {
                if let slot = session.slot {
                    notes.append("key \(slot + 1) forgets session \(Self.short(session.id)): it ended "
                        + "\(Int(now.timeIntervalSince(ended) / 3600)) h ago")
                }
                remove(session.id)
            }
        }
        return slots != before
    }

    public func owner(of slot: Int) -> Session? {
        sessions.values.first { $0.slot == slot }
    }

    public var lights: [SlotLight] {
        slots.enumerated().map { $1.light(slot: $0) }
    }

    /// The lights as the user's settings want them. The keys in `selected` pulse. `dimmed` turns
    /// everything off.
    public func lights(_ lighting: Config.Lighting, selected: Set<Int> = [], dimmed: Bool = false) -> [SlotLight] {
        slots.enumerated().map { slot, status in
            (dimmed ? AgentStatus.off : status).light(slot: slot, brightness: lighting.brightness,
                                                      selected: selected.contains(slot), color: lighting.color(status))
        }
    }

    /// The Agent Keys of the sessions that live in these places.
    public func slots(showing hosts: [SessionHost]) -> Set<Int> {
        Set(sessions.values.compactMap { session in
            guard let host = session.host, hosts.contains(host) else { return nil }
            return session.slot
        })
    }

    /// Sessions that are busy or waiting for their person, and whose record can be read.
    public var watchable: [Session] {
        sessions.values.filter { ($0.status == .working || $0.status == .needsYou) && $0.transcript != nil }
    }

    /// The person stopped this session's turn: it is idle now. Returns true if the lights changed.
    @discardableResult
    public mutating func stopped(_ id: String, at now: Date = Date()) -> Bool {
        guard var session = sessions[id] else { return false }
        let before = slots
        session.status = .idle
        session.heard = now
        sessions[id] = session
        if let slot = session.slot { slots[slot] = .idle }
        promote(at: now)
        return slots != before
    }

    private mutating func report(_ id: String, _ status: AgentStatus, pid: Int?, cwd: String?, host: SessionHost?,
                                 transcript: String?, at now: Date) {
        clock += 1
        let known = sessions[id] != nil
        var session = sessions[id] ?? Session(id: id, status: status, slot: nil, pid: nil, cwd: nil, seen: clock)
        if session.ended != nil {
            session.ended = nil
            if let slot = session.slot { notes.append("session \(Self.short(id)) is back on key \(slot + 1)") }
        }
        // The Claude app session it lives in may still hold a key, through a session that ended there.
        if !known, let host, let before = sessions.values.first(where: { $0.ended != nil && $0.host == host }) {
            session.slot = before.slot
            // A pin is on the Claude app session, whichever Claude Code session runs in it.
            session.pinned = before.pinned
            sessions[before.id] = nil
            if let slot = before.slot {
                notes.append("session \(Self.short(id)) takes over key \(slot + 1) from session "
                    + "\(Self.short(before.id)), which ended in the same Claude app session")
            }
        }
        let hadKey = session.slot != nil
        session.status = status
        session.seen = clock
        if let pid { session.pid = pid }
        if let cwd { session.cwd = cwd }
        if let host { session.host = host }
        if let transcript { session.transcript = transcript }
        session.heard = now
        if session.slot == nil {
            if let wanted = reserved, owner(of: wanted) == nil { session.slot = wanted } else { session.slot = freeSlot() }
            reserved = nil
        }
        sessions[id] = session
        if let slot = session.slot { slots[slot] = status }
        if !hadKey, let slot = session.slot {
            notes.append("session \(Self.short(id)) gets key \(slot + 1)")
        }

        if sessions.count > Self.maxSessions,
           let oldest = sessions.values.filter({ $0.slot == nil }).min(by: { $0.seen < $1.seen }) {
            sessions[oldest.id] = nil
        }
        promote(at: now)
        if !known, let fresh = sessions[id], fresh.slot == nil {
            notes.append("session \(Self.short(id)) waits: every key is taken")
        }
    }

    /// How much a session wants its person's eye. The six that want it most hold the keys.
    private static func urgency(_ session: Session) -> Int {
        switch session.status {
        case .needsYou: return 4
        case .done, .failed: return 3
        case .working: return 2
        case .idle, .off: return session.ended == nil ? 1 : 0
        }
    }

    /// While a session without a key wants its person more than a session with one, the key
    /// changes hands. The least urgent holder gives up first (ended, then idle, then working,
    /// then unread), and among equals the one heard from longest ago. A holder that still
    /// runs then waits for a key; one that ended is forgotten. The session on screen and one
    /// whose key was just pressed keep their keys.
    private mutating func promote(at now: Date = Date()) {
        guard urgentFirst else {
            settle()
            return
        }
        while let waiting = mostUrgentWaiting(),
              let holder = sessions.values.filter({ $0.slot != nil && !keepsKey($0, at: now) }).min(by: Self.givesUpBefore),
              Self.urgency(waiting) > Self.urgency(holder), let slot = holder.slot {
            if holder.ended != nil { sessions[holder.id] = nil } else { sessions[holder.id]?.slot = nil }
            sessions[waiting.id]?.slot = slot
            slots[slot] = waiting.status
            handovers.append(Handover(slot: slot, from: holder.id, to: waiting.id))
            notes.append("key \(slot + 1) goes from session \(Self.short(holder.id)) "
                + "(\(holder.ended != nil ? "ended" : holder.status.rawValue)) to session "
                + "\(Self.short(waiting.id)) (\(waiting.status.rawValue))")
        }
    }

    /// The session without a key that wants its person most. Among those that need their
    /// person, the longest wait; among the rest, the latest to do something.
    private func mostUrgentWaiting() -> Session? {
        sessions.values.filter { $0.slot == nil }.max { one, other in
            let (a, b) = (Self.urgency(one), Self.urgency(other))
            if a != b { return a < b }
            return one.status == .needsYou ? one.seen > other.seen : one.seen < other.seen
        }
    }

    private static func givesUpBefore(_ one: Session, _ other: Session) -> Bool {
        let (a, b) = (urgency(one), urgency(other))
        if a != b { return a < b }
        if let first = one.ended, let second = other.ended, first != second { return first < second }
        return one.seen < other.seen
    }

    private func keepsKey(_ session: Session, at now: Date) -> Bool {
        if session.pinned { return true }
        if let host = session.host, onScreen.contains(host) { return true }
        if let pressed = session.pressed, now.timeIntervalSince(pressed) < Self.pressedSeconds { return true }
        return false
    }

    /// The session's process is over. One that lives in the Claude app keeps its key for a
    /// while, so a press opens it again. What it had finished stays unread; anything else
    /// shows as idle.
    private mutating func end(_ id: String, at now: Date) {
        guard var session = sessions[id], session.ended == nil else { return }
        // A newer session in the same Claude app session has its own key already.
        let newer = sessions.values.first { $0.id != id && $0.ended == nil && $0.host != nil && $0.host == session.host }
        if session.pinned, let slot = session.slot, let newer {
            // The pin is on the Claude app session: the newer session moves to the pinned key.
            sessions[id] = nil
            sessions[newer.id]?.slot = slot
            sessions[newer.id]?.pinned = true
            slots[slot] = newer.status
            notes.append("session \(Self.short(newer.id)) takes over key \(slot + 1) and its pin from session "
                + "\(Self.short(id)), which ended in the same Claude app session")
            if let old = newer.slot, old != slot {
                slots[old] = .off
                fill(old)
            }
            promote(at: now)
            return
        }
        let twin = newer != nil
        // A pinned session that can be opened again keeps its key even when ended ones are not remembered.
        guard rememberSeconds > 0 || session.pinned, let slot = session.slot, session.host != nil, !twin else {
            if let slot = session.slot { notes.append("session \(Self.short(id)) ended: key \(slot + 1) is free") }
            remove(id)
            return
        }
        session.ended = now
        session.pid = nil
        session.transcript = nil
        if session.status != .done, session.status != .failed { session.status = .idle }
        sessions[id] = session
        slots[slot] = session.status
        notes.append("session \(Self.short(id)) ended: key \(slot + 1) remembers it")
        promote(at: now)
    }

    /// A session that waits for a key takes the key of one that has ended: the one that ended
    /// longest ago first, and those with nothing unread before the others.
    private mutating func settle() {
        while sessions.values.contains(where: { $0.slot == nil && $0.ended == nil }),
              let gone = sessions.values.filter({ $0.slot != nil && $0.ended != nil && !$0.pinned }).min(by: { one, other in
                  (one.status == .idle ? 0 : 1, one.ended ?? .distantPast) < (other.status == .idle ? 0 : 1, other.ended ?? .distantPast)
              }) {
            if let slot = gone.slot {
                notes.append("key \(slot + 1) forgets session \(Self.short(gone.id)), which ended: a session waits for a key")
            }
            remove(gone.id)
        }
    }

    private mutating func remove(_ id: String) {
        guard let gone = sessions.removeValue(forKey: id), let slot = gone.slot else { return }
        slots[slot] = .off
        fill(slot)
    }

    /// A free key goes to the waiting session that wants its person most; with that rule off,
    /// to whoever has waited with the most recent activity.
    private mutating func fill(_ slot: Int) {
        let waiting = sessions.values.filter { $0.slot == nil }
        if var next = urgentFirst ? mostUrgentWaiting() : waiting.max(by: { $0.seen < $1.seen }) {
            next.slot = slot
            sessions[next.id] = next
            slots[slot] = next.status
            notes.append("session \(Self.short(next.id)) gets key \(slot + 1)")
        }
    }

    // MARK: Across a restart

    /// Every session and its key, as text to keep while the bridge restarts.
    public func snapshot(at now: Date = Date()) -> String {
        let list = sessions.values.sorted { $0.seen < $1.seen }.map { session -> JSONValue in
            var pairs: [(String, JSONValue)] = [
                ("session", .string(session.id)), ("status", .string(session.status.rawValue)),
            ]
            if let slot = session.slot { pairs.append(("slot", .number(Double(slot)))) }
            if let pid = session.pid { pairs.append(("pid", .number(Double(pid)))) }
            if let cwd = session.cwd { pairs.append(("cwd", .string(cwd))) }
            if let host = session.host { pairs.append(("host", .string(host.description))) }
            if let transcript = session.transcript { pairs.append(("transcript", .string(transcript))) }
            if let ended = session.ended { pairs.append(("ended", .number(ended.timeIntervalSince1970.rounded()))) }
            if session.pinned { pairs.append(("pinned", .bool(true))) }
            return .object(pairs)
        }
        return JSONValue.object([
            ("version", .number(1)), ("saved", .number(now.timeIntervalSince1970.rounded())), ("sessions", .array(list)),
        ]).serialized
    }

    /// Takes back what `snapshot` wrote, into a state with no sessions yet. A session whose
    /// process is not the one it was (`sameProcess` gets its pid and when the text was written)
    /// counts as ended at that time: it keeps its key if it can be opened again, and comes
    /// back to life on that key with its next report. Returns how many sessions hold a key.
    @discardableResult
    public mutating func restore(_ text: String, sameProcess: (Int, Date) -> Bool) -> Int {
        guard sessions.isEmpty, let root = JSONValue.parse(text), root["version"]?.int == 1,
              let stamp = root["saved"]?.double, case let .array(list)? = root["sessions"] else { return 0 }
        let saved = Date(timeIntervalSince1970: stamp)
        for item in list.prefix(Self.maxSessions) {
            guard let id = item["session"]?.string, !id.isEmpty, sessions[id] == nil,
                  let status = item["status"]?.string.flatMap(AgentStatus.init(rawValue:)), status != .off else { continue }
            clock += 1
            var session = Session(id: id, status: status, slot: nil, pid: item["pid"]?.int, cwd: item["cwd"]?.string, seen: clock)
            if let slot = item["slot"]?.int, slots.indices.contains(slot), owner(of: slot) == nil { session.slot = slot }
            session.host = item["host"]?.string.flatMap { SessionHost($0) }
            if let record = item["transcript"]?.string, record.hasPrefix("/") { session.transcript = record }
            session.ended = item["ended"]?.double.map { Date(timeIntervalSince1970: $0) }
            session.pinned = item["pinned"]?.bool == true && session.slot != nil
            sessions[id] = session
            if let slot = session.slot { slots[slot] = status }
        }
        for session in sessions.values.sorted(by: { $0.seen < $1.seen }) where session.ended == nil {
            if let pid = session.pid, sameProcess(pid, saved) { continue }
            end(session.id, at: saved)
        }
        notes = []
        return sessions.values.filter { $0.slot != nil }.count
    }

    private func freeSlot() -> Int? {
        let taken = Set(sessions.values.compactMap(\.slot))
        return (0 ..< Self.slotCount).first { !taken.contains($0) }
    }
}

public enum Reply {
    public static let ok = JSONValue.object([("ok", .bool(true))]).serialized

    /// The answer to "orca.chats": Orca's open Claude chats, by Orca's session ID.
    public static func orcaChats(_ chats: [OrcaChat]) -> String {
        JSONValue.object([
            ("ok", .bool(true)),
            ("chats", .array(chats.map { chat in
                .object([("session", .string(chat.id)), ("title", .string(chat.title)),
                         ("status", .string(chat.status.rawValue)), ("worktree", .string(chat.worktree))])
            })),
        ]).serialized
    }

    /// One command in the answer to "commands": the controls that run it, what it does in
    /// the target asked about, and what it does where no app has an entry of its own.
    public struct CommandRow: Sendable, Equatable {
        public var name: String
        /// What people call it, such as Approve. The name when it has no other.
        public var title: String
        /// The controls that run it, as the window names them.
        public var controls: [String]
        public var here: [(trigger: String, actions: [String])]
        public var elsewhere: [(trigger: String, actions: [String])]

        public init(name: String, controls: [String], here: [(trigger: String, actions: [String])],
                    elsewhere: [(trigger: String, actions: [String])]) {
            self.name = name
            title = Config.commandTitles[name] ?? name
            self.controls = controls
            self.here = here
            self.elsewhere = elsewhere
        }

        public static func == (first: CommandRow, second: CommandRow) -> Bool {
            first.name == second.name && first.controls == second.controls
                && first.here.elementsEqual(second.here, by: ==) && first.elsewhere.elementsEqual(second.elsewhere, by: ==)
        }
    }

    public static func commands(_ rows: [CommandRow]) -> String {
        func lists(_ lists: [(trigger: String, actions: [String])]) -> JSONValue {
            .object(lists.map { ($0.trigger, .array($0.actions.map(JSONValue.string))) })
        }
        return JSONValue.object([
            ("ok", .bool(true)),
            ("commands", .array(rows.map { row in
                .object([("name", .string(row.name)), ("title", .string(row.title)),
                         ("controls", .array(row.controls.map(JSONValue.string))),
                         ("here", lists(row.here)), ("elsewhere", lists(row.elsewhere))])
            })),
        ]).serialized
    }

    public static func error(_ message: String) -> String {
        JSONValue.object([("ok", .bool(false)), ("error", .string(message))]).serialized
    }

    /// What macOS lets the bridge do, as the bridge itself sees it.
    public struct Access: Sendable, Equatable {
        public var inputMonitoring: InputMonitoring
        public var accessibility: Bool

        public init(inputMonitoring: InputMonitoring, accessibility: Bool) {
            self.inputMonitoring = inputMonitoring
            self.accessibility = accessibility
        }
    }

    /// `orca` is Orca's layer and the chats on its keys, when the config gives Orca a layer.
    public static func state(_ state: BridgeState, pad: PadInfo?, status: DeviceStatus? = nil,
                             shown: [SessionHost] = [], access: Access? = nil,
                             orca: (layer: Int, keys: OrcaKeys)? = nil) -> String {
        let sessions = state.sessions.values
            .sorted { ($0.slot ?? Int.max, $0.id) < ($1.slot ?? Int.max, $1.id) }
            .map { session -> JSONValue in
                var pairs: [(String, JSONValue)] = [
                    ("slot", session.slot.map { .number(Double($0)) } ?? .null),
                    ("session", .string(session.id)),
                    ("status", .string(session.status.rawValue)),
                ]
                if let cwd = session.cwd { pairs.append(("cwd", .string(cwd))) }
                if let pid = session.pid { pairs.append(("pid", .number(Double(pid)))) }
                if let host = session.host { pairs.append(("host", .string(host.description))) }
                if session.ended != nil { pairs.append(("ended", .bool(true))) }
                if session.pinned { pairs.append(("pinned", .bool(true))) }
                return .object(pairs)
            }
        var pairs: [(String, JSONValue)] = [
            ("ok", .bool(true)),
            ("connected", .bool(pad != nil)),
            ("slots", .array(state.slots.map { .string($0.rawValue) })),
            ("sessions", .array(sessions)),
        ]
        if !shown.isEmpty {
            pairs.append(("onScreen", .array(shown.map { .string($0.description) })))
            pairs.append(("pulsing", .array(state.slots(showing: shown).sorted().map { .number(Double($0)) })))
        }
        if let pad {
            pairs.append(("model", .string(pad.model)))
            if let firmware = status?.firmware { pairs.append(("firmware", .string(firmware))) }
            pairs.append(("transport", .string(pad.transport)))
            if let layer = status?.layer { pairs.append(("layer", .number(Double(layer)))) }
            if let battery = status?.battery { pairs.append(("battery", .number(Double(battery)))) }
            if let charging = status?.charging { pairs.append(("charging", .bool(charging))) }
        }
        if let access {
            pairs.append(("inputMonitoring", .string(access.inputMonitoring.rawValue)))
            pairs.append(("accessibility", .bool(access.accessibility)))
        }
        if let orca {
            let keys = (0 ..< BridgeState.slotCount).compactMap { slot -> JSONValue? in
                guard let chat = orca.keys.owner(of: slot) else { return nil }
                var pairs: [(String, JSONValue)] = [
                    ("slot", .number(Double(slot))), ("session", .string(chat.id)), ("status", .string(chat.status.rawValue)),
                ]
                if chat.ended != nil { pairs.append(("closed", .bool(true))) }
                if let title = orca.keys.titles[chat.id] { pairs.append(("title", .string(title))) }
                return .object(pairs)
            }
            pairs.append(("orca", .object([
                ("layer", .number(Double(orca.layer))),
                ("slots", .array(orca.keys.slots.map { .string($0.rawValue) })),
                ("keys", .array(keys)),
            ])))
        }
        return JSONValue.object(pairs).serialized
    }

    public static func event(_ event: PadEvent) -> String {
        switch event {
        case let .key(name, action, _):
            var pairs: [(String, JSONValue)] = [("event", .string("key")), ("name", .string(name))]
            if let action { pairs.append(("action", .number(Double(action)))) }
            if let slot = event.agentSlot { pairs.append(("slot", .number(Double(slot)))) }
            return JSONValue.object(pairs).serialized
        case let .joystick(angle, distance):
            return JSONValue.object([
                ("event", .string("joystick")), ("angle", .number(angle)), ("distance", .number(distance)),
            ]).serialized
        case let .unknown(method, params):
            return JSONValue.object([
                ("event", .string("unknown")), ("method", .string(method)), ("params", params),
            ]).serialized
        }
    }

    public static func connection(_ connected: Bool) -> String {
        JSONValue.object([("event", .string("pad")), ("connected", .bool(connected))]).serialized
    }
}

public enum BridgePaths {
    public static var directory: String {
        NSHomeDirectory() + "/Library/Application Support/micro-bridge"
    }

    public static var socket: String { directory + "/daemon.sock" }
    public static var config: String { directory + "/config.json" }
    /// Sessions and their keys, kept while the bridge restarts.
    public static var sessions: String { directory + "/sessions.json" }
}
