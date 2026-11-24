import Foundation

/// The six Agent Keys of Orca's layer. Each holds one chat, put there by hand: nothing but
/// its person takes a key or frees one (D-043). A chat that is not on a key is remembered for
/// a while, so a key that takes it knows what it is doing.
///
/// A chat is a `Session` whose id is Orca's session ID and whose host says so. `ended` on a
/// chat means its tab was closed: on a key it stays, dim, until the key is freed (D-054).
public struct OrcaKeys: Sendable, Equatable {
    /// Chats remembered at most, counting those on no key.
    static let maxChats = 32
    /// How bright a key with a closed chat is, against a key with an open one.
    public static let dimBrightness = 0.12

    public private(set) var chats: [String: Session] = [:]
    private var notes: [String] = []
    private var clock = 0

    public init() {}

    private static func short(_ id: String) -> String { String(id.prefix(8)) }

    /// What happened to chats and keys since the last call, oldest first, for the log.
    public mutating func takeNotes() -> [String] {
        defer { notes = [] }
        return notes
    }

    public func owner(of slot: Int) -> Session? {
        chats.values.first { $0.slot == slot }
    }

    /// What each key shows: its chat's status, `.off` for a key with no chat.
    public var slots: [AgentStatus] {
        (0 ..< BridgeState.slotCount).map { owner(of: $0)?.status ?? .off }
    }

    /// The keys whose chat is closed.
    public var dimSlots: Set<Int> {
        Set(chats.values.compactMap { $0.ended != nil ? $0.slot : nil })
    }

    /// The lights as the user's settings want them. A closed chat's key is dim white.
    public func lights(_ lighting: Config.Lighting, dimmed: Bool = false) -> [SlotLight] {
        (0 ..< BridgeState.slotCount).map { slot in
            guard !dimmed, let chat = owner(of: slot) else { return AgentStatus.off.light(slot: slot) }
            if chat.ended != nil {
                return AgentStatus.idle.light(slot: slot, brightness: lighting.brightness * Self.dimBrightness,
                                              color: lighting.color(.idle))
            }
            return chat.status.light(slot: slot, brightness: lighting.brightness, color: lighting.color(chat.status))
        }
    }

    /// A chat said what it is doing. Returns true if a key's light changed.
    @discardableResult
    public mutating func report(_ id: String, _ status: AgentStatus, pid: Int? = nil, cwd: String? = nil,
                                transcript: String? = nil, at now: Date = Date()) -> Bool {
        guard status != .off else { return end(id, at: now) }
        let before = shown
        clock += 1
        var chat = chats[id] ?? Session(id: id, status: status, slot: nil, pid: nil, cwd: nil, seen: clock)
        if chat.ended != nil, let slot = chat.slot { notes.append("chat \(Self.short(id)) is open again on key \(slot + 1)") }
        chat.ended = nil
        chat.host = .orcaChat(id)
        chat.status = status
        chat.seen = clock
        chat.heard = now
        if let pid { chat.pid = pid }
        if let cwd { chat.cwd = cwd }
        if let transcript { chat.transcript = transcript }
        chats[id] = chat
        if chats.count > Self.maxChats,
           let oldest = chats.values.filter({ $0.slot == nil }).min(by: { $0.seen < $1.seen }) {
            chats[oldest.id] = nil
        }
        return shown != before
    }

    /// The chat's tab was closed, or its process is gone. On a key it stays, dim; on no key it
    /// is forgotten. What it had finished stays unread.
    @discardableResult
    public mutating func end(_ id: String, at now: Date = Date()) -> Bool {
        guard var chat = chats[id], chat.ended == nil else { return false }
        guard let slot = chat.slot else {
            chats[id] = nil
            return false
        }
        chat.ended = now
        chat.pid = nil
        chat.transcript = nil
        if chat.status != .done, chat.status != .failed { chat.status = .idle }
        chats[id] = chat
        notes.append("chat \(Self.short(id)) was closed: key \(slot + 1) keeps it and goes dim")
        return true
    }

    /// The chats whose process is gone.
    public func gone(isAlive: (Int) -> Bool) -> [String] {
        chats.values.filter { chat in chat.ended == nil && chat.pid.map { !isAlive($0) } == true }.map(\.id).sorted()
    }

    /// The chat's process is gone: it does nothing any more. A chat on no key is forgotten.
    /// True when it is on a key: Orca then says whether its tab is closed too.
    @discardableResult
    public mutating func exited(_ id: String, at now: Date = Date()) -> Bool {
        guard var chat = chats[id], chat.ended == nil else { return false }
        guard chat.slot != nil else {
            chats[id] = nil
            return false
        }
        chat.pid = nil
        chat.heard = now
        if chat.status != .done, chat.status != .failed { chat.status = .idle }
        chats[id] = chat
        return true
    }

    /// Orca has the chat's tab open again: its key is lit again. True if it was closed.
    @discardableResult
    public mutating func reopen(_ id: String) -> Bool {
        guard let chat = chats[id], chat.ended != nil else { return false }
        chats[id]?.ended = nil
        if let slot = chat.slot { notes.append("chat \(Self.short(id)) is open again on key \(slot + 1)") }
        return true
    }

    /// Forgets a chat that is on no key.
    public mutating func forget(_ id: String) {
        if chats[id]?.slot == nil { chats[id] = nil }
    }

    /// Puts a chat on an empty key. `status` is what Orca says the chat is doing, for a chat
    /// that has not reported yet. False when the key is taken, or the chat is on a key already.
    @discardableResult
    public mutating func take(slot: Int, chat id: String, status: AgentStatus = .idle, at now: Date = Date()) -> Bool {
        guard (0 ..< BridgeState.slotCount).contains(slot), owner(of: slot) == nil else { return false }
        if let other = chats[id]?.slot {
            notes.append("chat \(Self.short(id)) is on key \(other + 1) already")
            return false
        }
        clock += 1
        var chat = chats[id] ?? Session(id: id, status: status == .off ? .idle : status, slot: nil, pid: nil, cwd: nil, seen: clock)
        chat.host = .orcaChat(id)
        chat.slot = slot
        chats[id] = chat
        notes.append("key \(slot + 1) takes chat \(Self.short(id)) (\(chat.status.rawValue))")
        return true
    }

    /// The key lets its chat go. An open chat is still remembered, a closed one is forgotten.
    /// Returns the chat it held.
    @discardableResult
    public mutating func free(slot: Int) -> Session? {
        guard let chat = owner(of: slot) else { return nil }
        if chat.ended != nil { chats[chat.id] = nil } else { chats[chat.id]?.slot = nil }
        notes.append("key \(slot + 1) is free: it held chat \(Self.short(chat.id))")
        return chat
    }

    /// A tap on a key marks what its chat finished as seen.
    @discardableResult
    public mutating func acknowledge(slot: Int) -> Bool {
        guard let chat = owner(of: slot), chat.status == .done || chat.status == .failed else { return false }
        chats[chat.id]?.status = .idle
        return true
    }

    /// Chats that are busy or waiting for their person, and whose record can be read.
    public var watchable: [Session] {
        chats.values.filter { ($0.status == .working || $0.status == .needsYou) && $0.transcript != nil }
    }

    /// The person stopped this chat's turn: it is idle now. Returns true if a key's light changed.
    @discardableResult
    public mutating func stopped(_ id: String, at now: Date = Date()) -> Bool {
        guard var chat = chats[id] else { return false }
        let before = shown
        chat.status = .idle
        chat.heard = now
        chats[id] = chat
        return shown != before
    }

    /// What the keys show, to tell whether a change is one the pad must hear of.
    private var shown: [String] {
        (0 ..< BridgeState.slotCount).map { slot in
            guard let chat = owner(of: slot) else { return "" }
            return chat.id + (chat.ended != nil ? " closed " : " ") + chat.status.rawValue
        }
    }

    // MARK: Across a restart

    /// The chats on keys, as text to keep while the bridge or Orca restarts.
    public func snapshot(at now: Date = Date()) -> String {
        let list = chats.values.filter { $0.slot != nil }.sorted { ($0.slot ?? 0) < ($1.slot ?? 0) }.map { chat -> JSONValue in
            var pairs: [(String, JSONValue)] = [
                ("session", .string(chat.id)), ("status", .string(chat.status.rawValue)),
                ("slot", .number(Double(chat.slot ?? 0))),
            ]
            if let pid = chat.pid { pairs.append(("pid", .number(Double(pid)))) }
            if let cwd = chat.cwd { pairs.append(("cwd", .string(cwd))) }
            if let transcript = chat.transcript { pairs.append(("transcript", .string(transcript))) }
            if let ended = chat.ended { pairs.append(("ended", .number(ended.timeIntervalSince1970.rounded()))) }
            return .object(pairs)
        }
        return JSONValue.object([
            ("version", .number(1)), ("saved", .number(now.timeIntervalSince1970.rounded())), ("chats", .array(list)),
        ]).serialized
    }

    /// Takes back what `snapshot` wrote, into keys that hold nothing yet. A chat whose process
    /// is not the one it was (`sameProcess` gets its pid and when the text was written) shows
    /// as closed until it reports again. Returns how many keys hold a chat.
    @discardableResult
    public mutating func restore(_ text: String, sameProcess: (Int, Date) -> Bool) -> Int {
        guard chats.isEmpty, let root = JSONValue.parse(text), root["version"]?.int == 1,
              let stamp = root["saved"]?.double, case let .array(list)? = root["chats"] else { return 0 }
        let saved = Date(timeIntervalSince1970: stamp)
        for item in list.prefix(BridgeState.slotCount) {
            guard let id = item["session"]?.string, SessionHost("orca:" + id) != nil, chats[id] == nil,
                  let status = item["status"]?.string.flatMap(AgentStatus.init(rawValue:)), status != .off,
                  let slot = item["slot"]?.int, (0 ..< BridgeState.slotCount).contains(slot), owner(of: slot) == nil else { continue }
            clock += 1
            var chat = Session(id: id, status: status, slot: slot, pid: item["pid"]?.int, cwd: item["cwd"]?.string, seen: clock)
            chat.host = .orcaChat(id)
            if let record = item["transcript"]?.string, record.hasPrefix("/") { chat.transcript = record }
            chat.ended = item["ended"]?.double.map { Date(timeIntervalSince1970: $0) }
            chats[id] = chat
            // No known process: Orca says whether the chat is open when its key is tapped.
            if chat.ended == nil, let pid = chat.pid, !sameProcess(pid, saved) { end(id, at: saved) }
        }
        notes = []
        return chats.count
    }
}
