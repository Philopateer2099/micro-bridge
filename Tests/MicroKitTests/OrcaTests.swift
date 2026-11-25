import Foundation
@testable import MicroKit
import Testing

/// Orca's chats on the keys of Orca's layer: what the hook sends, what Orca's answers mean, and
/// what the daemon does with a report, a hold and a tap.
@MainActor
struct OrcaTests {
    static let blue = Int(AgentStatus.working.color)
    static let white = Int(AgentStatus.idle.color)
    static let green = Int(AgentStatus.done.color)
    static let orange = Int(AgentStatus.needsYou.color)
    static let red = Int(AgentStatus.failed.color)
    static let dark = [0, 0, 0, 0, 0, 0]
    static let one = "11111111-chat-one"
    static let two = "22222222-chat-two"
    static let place = "0123456789abcdef0123456789abcdef0123::/Users/x/proj/app"

    static func chat(_ id: String, _ title: String, _ status: AgentStatus = .idle) -> OrcaChat {
        OrcaChat(id: id, title: title, worktree: place, status: status)
    }

    static func tab(_ title: String, selected: Bool = false) -> OrcaTab {
        OrcaTab(title: title, selected: selected)
    }

    /// What the hook sends for a chat.
    static func report(_ id: String, _ status: String, pid: Int? = nil) -> String {
        #"{"op":"report","session":"\#(id)","status":"\#(status)","host":"orca:\#(id)""# + (pid.map { #","pid":\#($0)"# } ?? "") + "}"
    }

    static func take(_ slot: Int, _ id: String? = nil) -> String {
        #"{"op":"orca.take","slot":\#(slot)"# + (id.map { #","session":"\#($0)""# } ?? "") + "}"
    }

    /// Orca has layer 2, the pad is on it, and Orca is in front.
    static func bench(more: String = "") throws -> Bench {
        let bench = try OwnLayerTests.bench(more: more)
        bench.scene.front = Bench.orca
        bench.tick()
        bench.tap(to: 2)
        return bench
    }

    // MARK: The hook

    static let chatEnvironment = [
        "ORCA_AGENT_SESSION_ID": one, "ORCA_STRUCTURED_SESSION": "1", "CLAUDE_CODE_ENTRYPOINT": "orca",
    ]

    static func payload(_ event: String, _ extra: String = "") -> JSONValue {
        JSONValue.parse(#"{"session_id":"abc","cwd":"/proj","hook_event_name":""# + event + "\"" + extra + "}")!
    }

    @Test func aChatInOrcaReportsUnderOrcasID() throws {
        let request = try #require(ClaudeHook.request(for: Self.payload("UserPromptSubmit"), pid: 77,
                                                      environment: Self.chatEnvironment))
        #expect(request ==
            #"{"op":"report","session":"\#(Self.one)","status":"working","pid":77,"cwd":"/proj","host":"orca:\#(Self.one)"}"#)
        #expect(try Command.parse(request) ==
            .report(session: Self.one, status: .working, pid: 77, cwd: "/proj", host: .orcaChat(Self.one)))
        // Closing its tab ends it under the same ID.
        #expect(ClaudeHook.request(for: Self.payload("SessionEnd", #","reason":"other""#), pid: 77,
                                   environment: Self.chatEnvironment) == #"{"op":"end","session":"\#(Self.one)"}"#)
    }

    /// /clear ends Claude's session, and the chat and its key stay.
    @Test func clearDoesNotEndAChat() {
        let cleared = Self.payload("SessionEnd", #","reason":"clear""#)
        #expect(ClaudeHook.request(for: cleared, pid: 77, environment: Self.chatEnvironment) == nil)
        // Outside Orca it ends the session, as before.
        #expect(ClaudeHook.request(for: cleared, pid: 77) == #"{"op":"end","session":"abc"}"#)
    }

    /// A Claude Code that a chat's session started as a command has the chat's ID in its
    /// environment. It is not the chat: it must not light or dim the chat's key.
    @Test func aClaudeCodeStartedInsideAChatSendsNothing() {
        for event in ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd"] {
            #expect(ClaudeHook.request(for: Self.payload(event), pid: 77, environment: Self.chatEnvironment, nested: true) == nil,
                    "\(event)")
        }
        // Outside Orca such a session reports, as before.
        #expect(ClaudeHook.request(for: Self.payload("Stop"), pid: 77, nested: true) != nil)
    }

    @Test func theClaudeAppAndOrcasTerminalsComeBeforeTheChat() {
        var desktop = Self.chatEnvironment
        desktop["CLAUDE_CODE_HOST_SESSION_ID"] = "local_abc"
        #expect(ClaudeHook.request(for: Self.payload("Stop"), pid: nil, environment: desktop) ==
            #"{"op":"report","session":"abc","status":"done","cwd":"/proj","host":"claude:local_abc"}"#)
        // A terminal in Orca sends nothing, whatever else its environment holds.
        var terminal = Self.chatEnvironment
        terminal["ORCA_TERMINAL_HANDLE"] = "term_1"
        #expect(ClaudeHook.request(for: Self.payload("Stop"), pid: nil, environment: terminal) == nil)
        // An ID that is not a plain ID names no chat.
        #expect(ClaudeHook.request(for: Self.payload("Stop"), pid: nil, environment: ["ORCA_AGENT_SESSION_ID": "a b"]) ==
            #"{"op":"report","session":"abc","status":"done","cwd":"/proj"}"#)
    }

    // MARK: What Orca answers

    static let listed = """
    {"id":"1","ok":true,"result":{"agents":[
      {"orcaSessionId":"\(one)","kind":"chat","agent":"claude","state":"working","worktreeId":"\(place)",
       "title":"Fix the build","paneKey":"structured-agent-session-\(one):0a1b2c3d","lastAssistantMessage":"…"},
      {"orcaSessionId":"\(two)","kind":"chat","agent":"claude","worktreeId":"\(place)","title":"New chat"},
      {"orcaSessionId":null,"kind":"terminal","agent":"claude","state":"done","worktreeId":"\(place)","title":"zsh"},
      {"orcaSessionId":"33333333-chat-three","kind":"chat","agent":"codex","state":"blocked",
       "worktreeId":"\(place)","title":"Another agent"}
    ],"truncated":false,"hostScope":"local"},"_meta":{}}
    """

    @Test func onlyClaudesChatsAreListed() throws {
        #expect(try Orca.chats(fromList: Self.listed).get() ==
            [Self.chat(Self.one, "Fix the build", .working), Self.chat(Self.two, "New chat")])
        #expect(Orca.status("blocked") == .needsYou)
        #expect(Orca.status("waiting") == .needsYou)
        #expect(Orca.status("done") == .done)
        #expect(Orca.status(nil) == .idle)
        #expect(Orca.chats(fromList: #"{"ok":false,"error":{"code":"x","message":"Orca is not running"}}"#) ==
            .failure(Orca.Problem("Orca: Orca is not running")))
        #expect(Orca.chats(fromList: "bash: orca: not found") == .failure(Orca.Problem("Orca: its answer could not be read")))
    }

    @Test func aChatWithNoPlaceIsClosed() throws {
        let open = """
        {"ok":true,"result":{"orcaSessionId":"\(Self.one)","kind":"chat","places":[
          {"orcaSessionId":"\(Self.one)","kind":"chat","agent":"claude","state":"waiting","worktreeId":"\(Self.place)","title":"Fix the build"}
        ]}}
        """
        #expect(try Orca.place(fromShow: open).get() == Self.chat(Self.one, "Fix the build", .needsYou))
        let closed = #"{"ok":true,"result":{"orcaSessionId":"\#(Self.one)","kind":"chat","places":[]}}"#
        #expect(try Orca.place(fromShow: closed).get() == nil)
        let unknown = #"{"ok":false,"error":{"code":"agent_unknown","message":"No agent with that ID"}}"#
        #expect(try Orca.place(fromShow: unknown).get() == nil)
        #expect(Orca.place(fromShow: #"{"ok":false,"error":{"code":"runtime","message":"Orca is not running"}}"#) ==
            .failure(Orca.Problem("Orca: Orca is not running")))
    }

    /// A tab's button says its state, its title, "Close tab" and the title again.
    @Test func aTabIsReadFromItsButton() {
        #expect(Orca.tab(label: "Working Fix the build Close tab Fix the build", classes: ["group", "bg-tab-active"]) ==
            Self.tab("Fix the build", selected: true))
        #expect(Orca.tab(label: "New chat Close tab New chat", classes: ["group"]) == Self.tab("New chat"))
        // A title with those words in it.
        #expect(Orca.tab(label: "Unread agent completion Notes on Close tab bugs Close tab Notes on Close tab bugs", classes: []) ==
            Self.tab("Notes on Close tab bugs"))
        // A tab that cannot be closed, such as a bot's Home, is named by the text it shows.
        #expect(Orca.tab(shown: "Home", label: "Home, Home: the bot's main chat.", classes: ["bg-tab-active"]) ==
            Self.tab("Home", selected: true))
        #expect(Orca.tab(shown: "Fix the build", label: "Working Fix the build Close tab Fix the build", classes: []) ==
            Self.tab("Fix the build"))
        #expect(Orca.tab(label: "New tab", classes: []) == nil)
        #expect(Orca.tab(label: "Close tab ", classes: []) == nil)
        #expect(Orca.tab(label: "One Close tab Two", classes: []) == nil)
    }

    @Test func aHoldTakesTheChatWhoseTabShows() {
        let chats = [Self.chat(Self.one, "Fix the build"), Self.chat(Self.two, "New chat")]
        let both = [Self.tab("Fix the build"), Self.tab("New chat", selected: true), Self.tab("zsh")]
        #expect(Orca.pick(tabs: both, chats: chats) == .chat(chats[1]))
        // A terminal's tab shows: the only chat of the workspace on screen.
        #expect(Orca.pick(tabs: [Self.tab("zsh", selected: true), Self.tab("New chat")], chats: chats) == .chat(chats[1]))
        // Several chats and none of them shows: the key cannot tell (D-044).
        let terminal = [Self.tab("Fix the build"), Self.tab("New chat"), Self.tab("zsh", selected: true)]
        #expect(Orca.pick(tabs: terminal, chats: chats) ==
            .unclear("the workspace on screen has 2 chats and the tab on screen is none of them"))
        // Tabs have no ID of their own: two chats with one title cannot be told apart.
        let twins = [Self.chat(Self.one, "New chat"), Self.chat(Self.two, "New chat")]
        #expect(Orca.pick(tabs: [Self.tab("New chat", selected: true)], chats: twins) ==
            .unclear("2 chats have the title of the tab on screen"))
        // A split view shows a tab in each part: a chat next to a terminal is the one, two chats are not.
        #expect(Orca.pick(tabs: [Self.tab("zsh", selected: true), Self.tab("New chat", selected: true)], chats: chats) == .chat(chats[1]))
        #expect(Orca.pick(tabs: [Self.tab("Fix the build", selected: true), Self.tab("New chat", selected: true)], chats: chats) ==
            .unclear("2 chats are on screen side by side"))
        #expect(Orca.pick(tabs: [Self.tab("zsh", selected: true)], chats: chats) == .unclear("the workspace on screen has no Claude chat"))
        #expect(Orca.pick(tabs: [], chats: chats) == .unclear("Orca's window shows no tabs"))
    }

    // MARK: The keys

    @Test func aKeyKeepsItsChatUntilItIsFreed() {
        var keys = OrcaKeys()
        // A chat on no key lights nothing.
        var changed = keys.report(Self.one, .working)
        #expect(!changed)
        var took = keys.take(slot: 2, chat: Self.one)
        #expect(took)
        #expect(keys.slots == [.off, .off, .working, .off, .off, .off])
        took = keys.take(slot: 2, chat: Self.two)
        #expect(!took)
        took = keys.take(slot: 3, chat: Self.one)
        #expect(!took)
        changed = keys.report(Self.one, .needsYou)
        #expect(changed)
        // Its tab is closed: the key keeps it, dim, and a chat that reports again is open again.
        changed = keys.end(Self.one)
        #expect(changed)
        #expect(keys.dimSlots == [2])
        #expect(keys.owner(of: 2)?.status == .idle)
        changed = keys.report(Self.one, .working)
        #expect(changed)
        #expect(keys.dimSlots.isEmpty)
        let freed = keys.free(slot: 2)
        #expect(freed?.id == Self.one)
        #expect(keys.slots.allSatisfy { $0 == .off })
        // The chat is still known: the next key that takes it shows what it is doing.
        took = keys.take(slot: 0, chat: Self.one)
        #expect(took)
        #expect(keys.owner(of: 0)?.status == .working)
        // A closed chat that is freed is forgotten.
        keys.end(Self.one)
        keys.free(slot: 0)
        #expect(keys.chats.isEmpty)
    }

    @Test func aChatThatFinishedKeepsThatAfterItsTabIsClosed() {
        var keys = OrcaKeys()
        keys.take(slot: 0, chat: Self.one, status: .done)
        var onKey = keys.exited(Self.one)
        #expect(onKey)
        #expect(keys.owner(of: 0)?.status == .done)
        keys.end(Self.one)
        #expect(keys.owner(of: 0)?.status == .done)
        let reopened = keys.reopen(Self.one)
        #expect(reopened)
        #expect(keys.dimSlots.isEmpty)
        // A chat on no key whose process ends is forgotten.
        keys.report(Self.two, .working, pid: 7)
        #expect(keys.gone(isAlive: { _ in false }) == [Self.two])
        onKey = keys.exited(Self.two)
        #expect(!onKey)
        #expect(keys.chats[Self.two] == nil)
    }

    @Test func aClosedChatsKeyIsDim() {
        var keys = OrcaKeys()
        keys.take(slot: 0, chat: Self.one, status: .working)
        keys.take(slot: 1, chat: Self.two, status: .working)
        keys.end(Self.two)
        let lights = keys.lights(Config.builtIn.lighting)
        #expect(lights[0] == AgentStatus.working.light(slot: 0))
        #expect(lights[1] == AgentStatus.idle.light(slot: 1, brightness: OrcaKeys.dimBrightness))
        #expect(lights[2] == AgentStatus.off.light(slot: 2))
        #expect(keys.lights(Config.builtIn.lighting, dimmed: true).allSatisfy { $0.effect == .off })
    }

    @Test func theKeysComeBackAfterARestart() {
        var keys = OrcaKeys()
        keys.report(Self.one, .needsYou, pid: 41, cwd: "/proj", transcript: "/records/one.jsonl")
        keys.take(slot: 4, chat: Self.one)
        keys.take(slot: 1, chat: Self.two, status: .done)
        keys.report("on-no-key", .working)
        let text = keys.snapshot()

        var same = OrcaKeys()
        let held = same.restore(text) { _, _ in true }
        #expect(held == 2)
        #expect(same.slots == [.off, .done, .off, .off, .needsYou, .off])
        #expect(same.owner(of: 4)?.transcript == "/records/one.jsonl")
        #expect(same.owner(of: 4)?.host == .orcaChat(Self.one))
        #expect(same.dimSlots.isEmpty)

        // Its process is another one now: closed until it reports again. A chat with no known
        // process stays as it was; Orca says whether it is open when its key is tapped.
        var later = OrcaKeys()
        later.restore(text) { _, _ in false }
        #expect(later.dimSlots == [4])
        #expect(later.owner(of: 1)?.ended == nil)
        var empty = OrcaKeys()
        let none = empty.restore("not json") { _, _ in true }
        #expect(none == 0)
    }

    // MARK: The socket

    @Test func theSocketTakesFreesAndShows() throws {
        #expect(try Command.parse(#"{"op":"orca.take","slot":2}"#) == .orcaTake(slot: 2))
        #expect(try Command.parse(Self.take(5, Self.one)) == .orcaTake(slot: 5, chat: Self.one))
        #expect(try Command.parse(#"{"op":"orca.free","slot":0}"#) == .orcaFree(slot: 0))
        #expect(try Command.parse(#"{"op":"orca.show","slot":3}"#) == .orcaShow(slot: 3))
        for bad in [#"{"op":"orca.take","slot":6}"#, #"{"op":"orca.take"}"#, #"{"op":"orca.take","slot":0,"session":"a b"}"#,
                    #"{"op":"orca.free","slot":-1}"#, #"{"op":"orca.jump","slot":0}"#] {
            #expect(throws: Command.Invalid.self, "\(bad)") { try Command.parse(bad) }
        }
    }

    @Test func theStateSaysWhatOrcasKeysHold() {
        var keys = OrcaKeys()
        keys.take(slot: 1, chat: Self.one, status: .working)
        keys.take(slot: 3, chat: Self.two)
        keys.end(Self.two)
        #expect(Reply.state(BridgeState(), pad: nil, orca: (2, keys)).hasSuffix(
            #""orca":{"layer":2,"slots":["off","working","off","idle","off","off"],"keys":["#
                + #"{"slot":1,"session":"\#(Self.one)","status":"working"},"#
                + #"{"slot":3,"session":"\#(Self.two)","status":"idle","closed":true}]}}"#))
        #expect(!Reply.state(BridgeState(), pad: nil).contains("orca"))
    }

    @Test func theSocketListsOrcasChats() throws {
        #expect(try Command.parse(#"{"op":"orca.chats"}"#) == .orcaChats)
        #expect(Reply.orcaChats([Self.chat(Self.one, "Fix the build", .working)])
            == #"{"ok":true,"chats":[{"session":"\#(Self.one)","title":"Fix the build","status":"working","#
            + #""worktree":"\#(Self.place)"}]}"#)
        #expect(Reply.orcaChats([]) == #"{"ok":true,"chats":[]}"#)
    }

    /// The bridge reads the tabs of this machine's Orca, so its questions go to this machine's
    /// Orca too, also when the shell it was started from points Orca's command somewhere else.
    @Test func orcasCommandStaysOnThisMachine() {
        let environment = Orca.environment(from: [
            "ORCA_ENVIRONMENT": "another-machine", "ORCA_PAIRING_CODE": "a-code", "HOME": "/Users/x", "PATH": "/usr/bin",
        ])
        #expect(environment["ORCA_ENVIRONMENT"] == nil && environment["ORCA_PAIRING_CODE"] == nil)
        #expect(environment["HOME"] == "/Users/x")
        #expect(environment["PATH"] == "/usr/local/bin:/opt/homebrew/bin:/usr/bin")
        #expect(Orca.environment(from: [:])["PATH"]?.hasSuffix(":/usr/bin:/bin:/usr/sbin:/sbin") == true)
    }

    /// A key knows what Orca calls its chat, so a key whose chat is closed can still say which
    /// one it was. The title is in the bridge's memory and its answers only.
    @Test func aKeyKnowsItsChatsTitleAndKeepsItOffTheFile() {
        var keys = OrcaKeys()
        keys.take(slot: 1, chat: Self.one, status: .working, title: "Fix the build")
        keys.take(slot: 3, chat: Self.two, title: "Two\nlines")
        #expect(keys.titles == [Self.one: "Fix the build", Self.two: "Two lines"])
        #expect(Reply.state(BridgeState(), pad: nil, orca: (2, keys)).contains(
            #"{"slot":1,"session":"\#(Self.one)","status":"working","title":"Fix the build"}"#))
        #expect(!keys.snapshot().contains("Fix the build"))
        #expect(!keys.takeNotes().joined().contains("Fix the build"))

        // Orca says what its chats are called now: a key's chat is renamed, a chat on no key
        // is not remembered, and a closed chat keeps the title it had.
        keys.end(Self.two)
        let changed = keys.learn(titles: [Self.one: "Fix the release build", "on-no-key": "Another chat"])
        #expect(changed)
        #expect(keys.titles == [Self.one: "Fix the release build", Self.two: "Two lines"])
        let again = keys.learn(titles: [Self.one: "Fix the release build"])
        #expect(!again)

        keys.free(slot: 1)
        keys.free(slot: 3)
        #expect(keys.titles.isEmpty)
    }

    // MARK: The daemon

    @Test func theBridgeAnswersWithOrcasChatsAndLearnsTheirTitles() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build", .working), Self.chat(Self.two, "New chat")]
        var answer = ""
        bench.daemon.orcaChats { answer = $0 }
        #expect(answer == Reply.orcaChats(bench.scene.chats))

        try bench.say(Self.take(2, Self.one))
        #expect(bench.daemon.orca.titles == [Self.one: "Fix the build"])
        bench.scene.chats = [Self.chat(Self.one, "Fix the release build", .working)]
        bench.daemon.orcaChats { answer = $0 }
        #expect(bench.daemon.orca.titles == [Self.one: "Fix the release build"])
        // A title is in no line of the log and not in the keys file.
        #expect(!bench.said("Fix the") && !bench.said("New chat"))
        let file = try String(contentsOfFile: bench.directory + "/orca-keys.json", encoding: .utf8)
        #expect(!file.contains("Fix the"))

        bench.scene.orcaProblem = "Orca is not running"
        bench.daemon.orcaChats { answer = $0 }
        #expect(answer == Reply.error("Orca is not running"))
    }

    /// D-053: a chat in Orca never takes a key of Claude's layer, and no key of Orca's until
    /// its person puts it there.
    @Test func aChatNeverTakesAKeyByItself() throws {
        let bench = try Self.bench()
        try bench.say(Self.report(Self.one, "working"))
        #expect(bench.pad.keyColors == Self.dark)
        bench.tap(to: 1)
        #expect(bench.pad.keyColors == Self.dark)
        // A Claude session next to it is on the first layer only.
        try bench.say(#"{"op":"report","session":"claude-one","status":"working"}"#)
        #expect(bench.pad.keyColors == [Self.blue, 0, 0, 0, 0, 0])
        bench.tap(to: 2)
        #expect(bench.pad.keyColors == Self.dark)
    }

    @Test func aHoldTakesTheChatOnScreenAndAHoldFreesIt() async throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build", .working), Self.chat(Self.two, "New chat")]
        bench.scene.tabs = [Self.tab("Fix the build", selected: true), Self.tab("New chat")]
        bench.pad.key("AG02", down: true)
        await bench.wait { bench.said("key 3 takes chat") }
        bench.pad.key("AG02", down: false)
        await bench.idle()
        #expect(bench.said("AG.hold key 3 on layer 2: the key takes the chat on screen in Orca"))
        #expect(bench.said("key 3 takes chat 11111111 (working)"))
        #expect(bench.pad.keyColors == [0, 0, Self.blue, 0, 0, 0])
        // The hold was no tap.
        #expect(bench.scene.shown.isEmpty)

        // What the chat reports shows on its key, on Orca's layer only.
        try bench.say(Self.report(Self.one, "needs-you"))
        #expect(bench.pad.keyColors == [0, 0, Self.orange, 0, 0, 0])
        bench.tap(to: 1)
        #expect(bench.pad.keyColors == Self.dark)
        bench.tap(to: 2)
        #expect(bench.pad.keyColors == [0, 0, Self.orange, 0, 0, 0])

        bench.pad.key("AG02", down: true)
        await bench.wait { bench.said("key 3 is free") }
        bench.pad.key("AG02", down: false)
        await bench.idle()
        #expect(bench.said("AG.hold key 3 on layer 2: the key lets its chat go"))
        #expect(bench.pad.keyColors == Self.dark)
        // The other chat can have the key now.
        try bench.say(Self.take(2, Self.two))
        #expect(bench.pad.keyColors == [0, 0, Self.white, 0, 0, 0])
    }

    @Test func aTapBringsTheChatOnScreen() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build", .done)]
        try bench.say(Self.take(0, Self.one))
        #expect(bench.pad.keyColors == [Self.green, 0, 0, 0, 0, 0])
        bench.pad.press("AG00")
        #expect(bench.said("AG.press key 1 on layer 2 in com.stablyai.orca: ack, jump, pane:chat"))
        #expect(bench.scene.shown == [Self.one])
        #expect(bench.said("key 1: chat 11111111: its tab is on screen now"))
        // What it finished counts as seen.
        #expect(bench.pad.keyColors == [Self.white, 0, 0, 0, 0, 0])
        // An empty key next to it says how it gets a chat.
        bench.pad.press("AG01")
        #expect(bench.said("AG.press key 2 on layer 2: no chat on this key. Hold it to take the chat on screen in Orca"))
        #expect(bench.scene.shown == [Self.one])
        // As a tap, by socket.
        try bench.say(#"{"op":"orca.show","slot":0}"#)
        #expect(bench.scene.shown == [Self.one, Self.one])
    }

    /// D-054: a closed chat stays on its key, dim. A tap does nothing, a hold frees the key.
    @Test func aClosedChatsKeyGoesDimAndIgnoresTaps() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        try bench.say(Self.report(Self.one, "working"))
        #expect(bench.pad.keyColors == [Self.blue, 0, 0, 0, 0, 0])

        // Its tab is closed: its process ends and Orca has no place for it.
        bench.scene.chats = []
        try bench.say(#"{"op":"end","session":"\#(Self.one)"}"#)
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
        #expect(bench.pad.keyColors == [Self.white, 0, 0, 0, 0, 0])
        #expect(abs((bench.pad.keyBrightness?.first ?? 0) - OrcaKeys.dimBrightness) < 0.001)

        bench.pad.press("AG00")
        #expect(bench.said("AG.press key 1 on layer 2: its chat is closed, the tap does nothing. Hold the key to free it"))
        #expect(bench.scene.shown.isEmpty)
        #expect(bench.pad.keyColors == [Self.white, 0, 0, 0, 0, 0])

        try bench.say(#"{"op":"orca.free","slot":0}"#)
        #expect(bench.pad.keyColors == Self.dark)
    }

    /// The process of a chat can end while its tab stays. Orca says so, and the key stays lit.
    @Test func aChatWhoseTabStaysKeepsItsKeyLit() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        try bench.say(Self.report(Self.one, "working"))
        try bench.say(#"{"op":"end","session":"\#(Self.one)"}"#)
        #expect(bench.said("chat 11111111's process ended, but Orca still has its tab: key 1 stays lit"))
        #expect(bench.pad.keyColors == [Self.white, 0, 0, 0, 0, 0])
        #expect(bench.pad.keyBrightness?.first == 1)
    }

    /// A process that died without a word is noticed within a few seconds.
    @Test func aChatWhoseProcessDiedIsAskedAbout() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        // No process has this number.
        try bench.say(Self.report(Self.one, "working", pid: 9_999_999))
        bench.scene.chats = []
        for _ in 0 ..< 5 { bench.tick() }
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
    }

    /// After a restart of Orca a chat's tab is back before the chat says anything.
    @Test func aChatThatIsOpenAgainAnswersTheNextTap() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.scene.chats = []
        try bench.say(#"{"op":"end","session":"\#(Self.one)"}"#)
        #expect(abs((bench.pad.keyBrightness?.first ?? 0) - OrcaKeys.dimBrightness) < 0.001)

        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        bench.pad.press("AG00")
        #expect(bench.said("chat 11111111 is open again on key 1"))
        #expect(bench.scene.shown == [Self.one])
        #expect(bench.pad.keyBrightness?.first == 1)
    }

    // MARK: Quiet chats (D-068)

    /// A chat taken from Orca's list that has not reported: the bridge knows no process of
    /// its own, so nothing ends when its tab is closed. Orca is asked which chats are open.
    @Test func aQuietChatsKeyGoesDimWhenItsTabIsClosed() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.tick()
        #expect(bench.scene.asked == 1)
        #expect(bench.pad.keyBrightness?.first == 1)

        bench.scene.chats = []
        for _ in 0 ..< Bench.watchEvery - 1 { bench.tick() }
        #expect(bench.scene.asked == 1)
        bench.tick()
        #expect(bench.scene.asked == 2)
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
        #expect(bench.pad.keyColors == [Self.white, 0, 0, 0, 0, 0])
        #expect(abs((bench.pad.keyBrightness?.first ?? 0) - OrcaKeys.dimBrightness) < 0.001)

        // A closed chat is asked about no more.
        for _ in 0 ... Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 2)
    }

    /// A chat whose process ended while its tab stayed is quiet too.
    @Test func aChatLeftWithoutItsProcessIsWatchedAsWell() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        try bench.say(Self.report(Self.one, "done"))
        try bench.say(#"{"op":"end","session":"\#(Self.one)"}"#)
        #expect(bench.said("chat 11111111's process ended, but Orca still has its tab: key 1 stays lit"))

        bench.scene.chats = []
        bench.tick()
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
    }

    /// A tab is closed by hand, in Orca. With another app in front nothing is asked, but for
    /// once when Orca leaves the front.
    @Test func quietChatsAreAskedAboutOnlyWhileOrcaIsInFront() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.tick()
        #expect(bench.scene.asked == 1)

        bench.scene.front = Bench.claude
        bench.tick()
        #expect(bench.scene.asked == 2)
        bench.scene.chats = []
        for _ in 0 ..< 2 * Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 2)
        #expect(!bench.said("was closed"))

        // Back in Orca, the first second asks.
        bench.scene.front = Bench.orca
        bench.tick()
        #expect(bench.scene.asked == 3)
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
    }

    /// Close a tab and switch away at once: the ask on leaving Orca sees it.
    @Test func aTabClosedJustBeforeLeavingOrcaIsSeen() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.tick()

        bench.scene.chats = []
        bench.scene.front = Bench.claude
        bench.tick()
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
    }

    /// Orca quit: it is not in front and not running. Its command line is left alone, and
    /// the key stays as it is.
    @Test func anOrcaThatQuitIsNotAsked() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.tick()
        #expect(bench.scene.asked == 1)

        bench.scene.chats = []
        bench.scene.running.remove(Bench.orca)
        bench.scene.front = Bench.claude
        for _ in 0 ... Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 1)
        #expect(bench.pad.keyBrightness?.first == 1)
    }

    /// Nobody closes a tab while nobody is at the Mac: Orca left in front overnight is not
    /// asked all night.
    @Test func nothingIsAskedWhileNobodyTouchesTheMac() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.tick()
        #expect(bench.scene.asked == 1)

        bench.scene.idle = 600
        for _ in 0 ..< 2 * Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 1)

        bench.scene.idle = 1
        bench.tick()
        #expect(bench.scene.asked == 2)
    }

    /// When Orca does not answer, nothing is known: the key stays lit, and the log says so once.
    @Test func anOrcaThatDoesNotAnswerLeavesAQuietChatsKeyLit() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.tick()

        bench.scene.chats = []
        bench.scene.orcaProblem = "Orca: it is not running"
        for _ in 0 ..< 2 * Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 3)
        #expect(bench.pad.keyBrightness?.first == 1)
        #expect(!bench.said("was closed"))
        #expect(bench.scene.lines.filter { $0.contains("could not ask Orca which chats are open (Orca: it is not running)") }.count == 1)

        bench.scene.orcaProblem = nil
        for _ in 0 ..< Bench.watchEvery { bench.tick() }
        #expect(bench.said("chat 11111111 was closed: key 1 keeps it and goes dim"))
    }

    /// Orca's list leaves out a chat put to sleep in the middle of a turn. Its tab is open,
    /// so its key stays lit, and Orca is asked about that chat once.
    @Test func aChatOrcasListLeavesOutKeepsItsKeyLit() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        bench.scene.asleep = bench.scene.chats
        bench.scene.chats = []
        for _ in 0 ... 2 * Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 3)
        #expect(bench.pad.keyBrightness?.first == 1)
        #expect(!bench.said("was closed"))
        #expect(bench.scene.lines.filter { $0.contains("Orca's list leaves out chat 11111111, but its tab is open: key 1 stays lit") }.count == 1)
    }

    /// A chat that reports has a process the bridge watches. Orca is not asked about it.
    @Test func aChatWithAKnownProcessIsNotAskedAbout() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        try bench.say(Self.take(0, Self.one))
        try bench.say(Self.report(Self.one, "working", pid: Int(ProcessInfo.processInfo.processIdentifier)))
        for _ in 0 ... Bench.watchEvery { bench.tick() }
        #expect(bench.scene.asked == 0)
        #expect(bench.pad.keyBrightness?.first == 1)
    }

    /// D-044: when the window does not single out one chat, the key says no and the log why.
    @Test func aHoldThatCannotTellWhichChatFlashesTheKey() async throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build"), Self.chat(Self.two, "New chat")]
        bench.scene.tabs = [Self.tab("Fix the build"), Self.tab("New chat"), Self.tab("zsh", selected: true)]
        try bench.say(Self.take(1))
        #expect(bench.said("key 2 takes no chat: the workspace on screen has 2 chats and the tab on screen is none of them"))
        await bench.wait { bench.pad.keyColors?[1] == Self.red }
        #expect(bench.pad.keyColors?[1] == Self.red)
        await bench.wait { bench.pad.requests.count > 0 && bench.pad.keyColors == Self.dark }
        #expect(bench.pad.keyColors == Self.dark)
    }

    @Test func aChatIsOnOneKeyOnly() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build")]
        bench.scene.tabs = [Self.tab("Fix the build", selected: true)]
        try bench.say(Self.take(0))
        try bench.say(Self.take(1))
        #expect(bench.said("key 2 takes no chat: that chat is on key 1 already"))
        var answer: String?
        bench.daemon.orcaCommand(.orcaTake(slot: 0)) { answer = $0 }
        #expect(answer == "key 1 holds a chat already: free it first")
        bench.daemon.orcaCommand(.orcaShow(slot: 4)) { answer = $0 }
        #expect(answer == "key 5 holds no chat")
        bench.daemon.orcaCommand(.orcaTake(slot: 4, chat: Self.two)) { answer = $0 }
        #expect(answer == "Orca has no open Claude chat with that ID")
    }

    @Test func anOrcaThatDoesNotAnswerIsSaid() throws {
        let bench = try Self.bench()
        bench.scene.orcaProblem = "Orca's command line (orca) is not installed"
        try bench.say(Self.take(0))
        #expect(bench.said("key 1 takes no chat: Orca's command line (orca) is not installed"))
        #expect(bench.pad.keyColors?.first != Self.blue)
    }

    /// `forget` from the socket frees a chat's key, as it frees a session's.
    @Test func forgetFreesAChatsKey() throws {
        let bench = try Self.bench()
        bench.scene.chats = [Self.chat(Self.one, "Fix the build", .working)]
        try bench.say(Self.take(3, Self.one))
        #expect(bench.pad.keyColors == [0, 0, 0, Self.blue, 0, 0])
        try bench.say(#"{"op":"forget","session":"\#(Self.one)"}"#)
        #expect(bench.pad.keyColors == Self.dark)
    }

    @Test func theKeysAreWrittenDownAndTakenBack() throws {
        let first = try Self.bench()
        first.scene.chats = [Self.chat(Self.one, "Fix the build", .needsYou)]
        try first.say(Self.take(5, Self.one))
        let text = try String(contentsOfFile: first.directory + "/orca-keys.json", encoding: .utf8)
        #expect(text.contains(#""session":"\#(Self.one)","status":"needs-you","slot":5"#))
        // Nothing of what Orca shows is kept: no title, no folder.
        #expect(!text.contains("Fix the build"))

        let second = try OwnLayerTests.bench()
        try text.write(toFile: second.directory + "/orca-keys.json", atomically: true, encoding: .utf8)
        second.daemon.restoreOrcaKeys()
        #expect(second.said("Orca chats from before the restart: 1 keep their keys, 0 of them closed"))
        second.tick()
        second.tap(to: 2)
        #expect(second.pad.keyColors == [0, 0, 0, 0, 0, Self.orange])
    }

    /// Without a layer of its own, Orca's chats get no key at all: not one of Claude's either.
    @Test func withNoLayerOfItsOwnOrcasChatsGetNoKey() throws {
        let bench = try Bench(layers: "{}")
        bench.tick()
        try bench.say(Self.report(Self.one, "working"))
        #expect(bench.pad.keyColors == Self.dark)
        #expect(bench.said("a chat in Orca reported, but no layer is Orca's (layerApps): it gets no key"))
        var answer: String?
        bench.daemon.orcaCommand(.orcaTake(slot: 0)) { answer = $0 }
        #expect(answer?.hasPrefix("no layer is Orca's") == true)
    }

    /// A layer of the bridge's own that is not Orca's has no agents on its keys.
    @Test func anotherLayerOfTheBridgesOwnHasNoChats() throws {
        let bench = try Bench(layers: "{}", more: #""layerApps": {"2": ["com.apple.Notes"]},"#)
        bench.pad.keyLayers = [1, 2]
        bench.tick()
        bench.tap(to: 2)
        bench.pad.press("AG00")
        #expect(bench.said("AG.press key 1 on layer 2: no agent on this key, nothing to do"))
    }

    /// Approve and Decline press the buttons of Orca's permission card.
    @Test func approveAndDeclinePressOrcasCard() {
        let config = Config.builtIn
        #expect(config.actions(for: "ACT07", "press", app: Bench.orca).map(\.description) == ["click:native-chat-appearance/=Allow"])
        #expect(config.actions(for: "ACT08", "press", app: Bench.orca).map(\.description) == ["click:native-chat-appearance/=Deny"])
        // In the Claude app they are what they were.
        #expect(config.actions(for: "ACT07", "press", app: Bench.claude).first?.description == "click:Suggested next actions/first")
        #expect(config.layer(ofApp: Bench.orca) == nil)
    }
}
