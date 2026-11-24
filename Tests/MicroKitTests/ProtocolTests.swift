import Foundation
import Testing
@testable import MicroKit

@Suite struct FramingTests {
    @Test func splitsIntoSixtyOneByteChunks() {
        let message = [UInt8](repeating: 0x41, count: 130)
        let reports = Framing.reports(for: message)
        #expect(reports.count == 3)
        #expect(reports.allSatisfy { $0.count == 64 && $0[0] == 0x06 && $0[1] == 2 })
        #expect(reports.map { Int($0[2]) } == [61, 61, 8])
        #expect(reports[2][3 ..< 11].allSatisfy { $0 == 0x41 })
        #expect(reports[2][11...].allSatisfy { $0 == 0 })
    }

    @Test func aWriteMacOSRefusesIsNotALostPad() {
        // 0xE00002E2: every write while the Mac is locked.
        guard case .writesRefused = PadError.writing(IOReturn(bitPattern: 0xE00002E2)) else {
            Issue.record("a refused write should keep the pad")
            return
        }
        guard case let .writeFailed(code) = PadError.writing(IOReturn(bitPattern: 0xE00002C0)) else {
            Issue.record("any other failure is a failed write")
            return
        }
        #expect(code == IOReturn(bitPattern: 0xE00002C0))
    }

    @Test func emptyMessageSendsNothing() {
        #expect(Framing.reports(for: []).isEmpty)
    }

    @Test func roundTripsThroughAssembler() {
        let text = #"{"id":7,"result":{"version":"0.4.1"}}"# + "\n"
        var assembler = LineAssembler()
        let lines = Framing.reports(for: Array(text.utf8)).flatMap { assembler.feed($0) }
        #expect(lines == [.init(channel: 2, text: #"{"id":7,"result":{"version":"0.4.1"}}"#)])
    }

    @Test func keepsUTF8SplitAcrossReports() {
        // "é" is two bytes; put the split between them.
        let text = String(repeating: "a", count: 60) + "é\n"
        var assembler = LineAssembler()
        let lines = Framing.reports(for: Array(text.utf8)).flatMap { assembler.feed($0) }
        #expect(lines.map(\.text) == [String(repeating: "a", count: 60) + "é"])
    }

    @Test func separatesChannelsAndHandlesCRLF() {
        var assembler = LineAssembler()
        var lines: [LineAssembler.Line] = []
        lines += Framing.reports(for: Array("boot ok\r\n".utf8), channel: .debug).flatMap { assembler.feed($0) }
        lines += Framing.reports(for: Array("{\"m\":\"x\"}\n".utf8), channel: .rpc).flatMap { assembler.feed($0) }
        #expect(lines == [.init(channel: 1, text: "boot ok"), .init(channel: 2, text: "{\"m\":\"x\"}")])
    }

    @Test func ignoresForeignAndMalformedReports() {
        var assembler = LineAssembler()
        var keyboard = [UInt8](repeating: 0, count: 64)
        keyboard[0] = 0x01
        #expect(assembler.feed(keyboard).isEmpty)
        var lying = [UInt8](repeating: 0, count: 64)
        lying[0] = 0x06; lying[1] = 2; lying[2] = 200
        #expect(assembler.feed(lying).isEmpty)
    }
}

@Suite struct RPCTests {
    @Test func requestMatchesVendorShape() {
        #expect(RPC.request(.status, id: 42) == #"{"method":"device.status","params":null,"id":42}"#)
    }

    @Test func requestParamsKeepOrderAndNumberFormat() {
        let light = AgentStatus.needsYou.light(slot: 2)
        let text = RPC.request(.threadsLighting, params: .array([light.json]), id: 1)
        #expect(text == #"{"method":"v.oai.thstatus","params":[{"id":2,"c":16739584,"b":1,"e":4,"s":0.4,"sk":0,"sa":0}],"id":1}"#)
    }

    @Test func escapesNonASCII() {
        let backslash = "\\"
        #expect(asciiEscaped("caf\u{e9} \u{1F39B}") == "caf" + backslash + "u00e9 " + backslash + "ud83c" + backslash + "udf9b")
    }

    @Test func onlySafeMethodsExist() {
        #expect(Set(Method.allCases.map(\.rawValue)) ==
            ["sys.version", "device.status", "v.oai.thstatus", "v.oai.rgbcfg", "lights.preview"])
    }

    @Test func decodesResponsesWithLongOrShortKeys() {
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: #"{"id":5,"result":"0.4.1"}"#) == .response(id: "5", method: nil, result: .string("0.4.1"), error: nil))
        #expect(assembler.feed(line: #"{"i":"6","result":null}"#) == .response(id: "6", method: nil, result: .null, error: nil))
    }

    @Test func keepsEchoedMethodOnResponses() {
        // Captured from firmware v0.6.1: replies echo the method after the id.
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: #"{"result":null,"id":817,"method":"host.focused_app"}"#) ==
            .response(id: "817", method: "host.focused_app", result: .null, error: nil))
    }

    @Test func decodesErrors() {
        var assembler = MessageAssembler()
        let message = assembler.feed(line: #"{"id":9,"error":{"code":-32601,"message":"Method not found"}}"#)
        #expect(message == .response(id: "9", method: nil, result: nil, error: RPCError(code: -32601, message: "Method not found")))
    }

    @Test func joinsMessageSplitOverLinesAndSkipsJunk() {
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: #"I (123) rpc: {"m":"v.oai.hid","#) == nil)
        #expect(assembler.feed(line: #""p":{"k":"AG03","act":1}}"#) ==
            .notification(method: "v.oai.hid", params: .object([("act", .number(1)), ("k", .string("AG03"))])))
        #expect(assembler.feed(line: "no json here") == nil)
    }
}

@Suite struct UnreadableTextTests {
    private let good = #"{"result":{"ok":1},"id":4,"method":"v.oai.thstatus"}"#

    private func isAnswerFour(_ incoming: Incoming?) -> Bool {
        if case let .response(id, _, _, _)? = incoming { return id == "4" }
        return false
    }

    @Test func aLineCutShortDoesNotBlockTheNextMessage() {
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: #"{"result":{"version":"v0.6.1","layer_in"#) == nil)
        #expect(isAnswerFour(assembler.feed(line: good)))
        #expect(assembler.takeDropped() == [#"{"result":{"version":"v0.6.1","layer_in"#])
        #expect(assembler.takeDropped().isEmpty)
    }

    @Test func twoMessagesRunTogetherLoseOnlyThemselves() {
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: #"{"result":{"ver{"result":null,"id":584}"#) == nil)
        #expect(isAnswerFour(assembler.feed(line: good)))
    }

    @Test func aMessageMayStillSpanLines() {
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: #"{"result":{"ok":1},"#) == nil)
        #expect(isAnswerFour(assembler.feed(line: #""id":4}"#)))
        #expect(assembler.takeDropped().isEmpty)
    }

    @Test func textThatNeverParsesIsDroppedAfterAFewLines() {
        var assembler = MessageAssembler()
        #expect(assembler.feed(line: "{broken") == nil)
        for _ in 1 ..< MessageAssembler.maxLines { #expect(assembler.feed(line: "more") == nil) }
        #expect(assembler.takeDropped().count == 1)
        // Nothing is pending now, so a line with no brace is ignored and a message parses.
        #expect(assembler.feed(line: "noise") == nil)
        #expect(isAnswerFour(assembler.feed(line: good)))
    }
}

@Suite struct StoppedTurnTests {
    private let question = #"{"type":"assistant","timestamp":"2026-11-12T19:04:12.100Z","message":{"content":[{"type":"tool_use","name":"AskUserQuestion"}]}}"#
    private let refused = #"{"type":"user","timestamp":"2026-11-12T19:04:43.200Z","message":{"content":[{"type":"tool_result","is_error":true,"content":"The user doesn't want to proceed"}]}}"#
    private let stopped = #"{"type":"user","timestamp":"2026-11-12T19:04:43.250Z","message":{"content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    private let plainStop = #"{"type":"user","timestamp":"2026-11-12T19:04:43Z","message":{"content":"[Request interrupted by user]"}}"#
    private let reply = #"{"type":"assistant","timestamp":"2026-11-12T19:05:00.000Z","message":{"content":[{"type":"text","text":"Done."}]}}"#
    private let other = #"{"type":"system","timestamp":"2026-11-12T19:05:01.000Z","subtype":"note"}"#

    @Test func aTurnStoppedByHandIsSeenInTheRecord() throws {
        let at = try #require(Transcript.interruptedAt(tail: [question, refused, stopped].joined(separator: "\n") + "\n"))
        #expect(abs(at.timeIntervalSince1970 - 1_794_510_283.25) < 0.01)
        // Entries that are neither side talking do not hide it, and a cut first line is skipped.
        #expect(Transcript.interruptedAt(tail: "t\":\"cut\"}\n" + [stopped, other].joined(separator: "\n")) != nil)
        #expect(Transcript.interruptedAt(tail: plainStop) != nil)
    }

    @Test func anOlderStopIsNotTheLatestWord() {
        #expect(Transcript.interruptedAt(tail: [stopped, reply].joined(separator: "\n")) == nil)
        #expect(Transcript.interruptedAt(tail: [question, refused].joined(separator: "\n")) == nil)
        #expect(Transcript.interruptedAt(tail: "") == nil)
    }

    @Test func aStoppedSessionGoesIdleAndIsNoLongerWatched() throws {
        var state = BridgeState()
        let heard = Date(timeIntervalSince1970: 1000)
        state.apply(.report(session: "a", status: .needsYou, pid: nil, cwd: nil, transcript: "/tmp/a.jsonl"), at: heard)
        state.apply(.report(session: "b", status: .working, pid: nil, cwd: nil))
        #expect(state.watchable.map(\.id) == ["a"])
        #expect(state.sessions["a"]?.heard == heard)
        let lightsChanged = state.stopped("a")
        #expect(lightsChanged)
        #expect(state.sessions["a"]?.status == .idle && state.slots[0] == .idle)
        #expect(state.watchable.isEmpty)
        let unknown = state.stopped("nobody")
        #expect(!unknown)
    }

    @Test func theHookPassesTheRecordPathOn() throws {
        let payload = try #require(JSONValue.parse(
            #"{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"abc","transcript_path":"/Users/x/.claude/projects/p/abc.jsonl"}"#))
        let request = try #require(ClaudeHook.request(for: payload, pid: nil))
        let command = try Command.parse(request)
        #expect(command == .report(session: "abc", status: .needsYou, pid: nil, cwd: nil,
                                   transcript: "/Users/x/.claude/projects/p/abc.jsonl"))
        #expect(throws: (any Error).self) { try Command.parse(#"{"op":"report","session":"a","status":"working","transcript":"relative.jsonl"}"#) }
    }
}

@Suite struct ClickGuardTests {
    @Test func aLandedClickQuietsItsOwnKeyForAMoment() {
        let start = Date(timeIntervalSince1970: 1000)
        var quiet = ClickGuard(seconds: 1)
        let before = quiet.blocks("ACT07#-1", at: start)
        quiet.landed("ACT07#-1", at: start)
        let soonAfter = quiet.blocks("ACT07#-1", at: start.addingTimeInterval(0.4))
        // Another key is not held back.
        let otherKey = quiet.blocks("ACT06#-1", at: start.addingTimeInterval(0.4))
        let later = quiet.blocks("ACT07#-1", at: start.addingTimeInterval(1.1))
        #expect(!before && soonAfter && !otherKey && !later)
    }

    @Test func zeroSecondsTurnsTheGuardOff() {
        let start = Date(timeIntervalSince1970: 1000)
        var quiet = ClickGuard(seconds: 0)
        quiet.landed("ACT07#-1", at: start)
        let blocked = quiet.blocks("ACT07#-1", at: start)
        #expect(!blocked)
    }
}

@Suite struct EventTests {
    @Test func parsesKeys() {
        let event = PadEvent(method: "v.oai.hid", params: .object([("k", .string("AG04")), ("act", .number(1)), ("ag", .number(4))]))
        #expect(event == .key(name: "AG04", action: 1, agent: 4))
        #expect(event.agentSlot == 4)
        #expect(PadEvent(method: "v.oai.hid", params: .object([("k", .string("ACT07"))])).agentSlot == nil)
        #expect(PadEvent(method: "v.oai.hid", params: .object([("k", .string("AG09"))])).agentSlot == nil)
    }

    @Test func parsesJoystick() {
        let event = PadEvent(method: "v.oai.rad", params: .object([("a", .number(0.25)), ("d", .number(0.9))]))
        #expect(event == .joystick(angle: 0.25, distance: 0.9))
    }

    @Test func keepsUnknownNotifications() {
        let event = PadEvent(method: "v.oai.enc", params: .number(1))
        #expect(event == .unknown(method: "v.oai.enc", params: .number(1)))
    }

    @Test func readsStatus() {
        let value = JSONValue.parse(#"{"version":"0.4.1","profile_index":0,"layer_index":1,"battery":87,"is_charging":true}"#)!
        let s = DeviceStatus(value)
        #expect(s.firmware == "0.4.1" && s.layer == 1 && s.battery == 87 && s.charging == true)
    }

    // MARK: A session that ended keeps its key

    private func app(_ name: String) -> SessionHost { .claudeDesktop("local_" + name) }

    @Test func aSessionThatEndsKeepsItsKey() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: 7, cwd: nil, host: app("aaaa")))
        state.apply(.report(session: "b", status: .working, pid: 8, cwd: nil, host: app("bbbb")))
        state.apply(.end(session: "a"))
        #expect(state.slots[0] == .idle && state.slots[1] == .working)
        #expect(state.owner(of: 0)?.host == app("aaaa"))
        #expect(state.sessions["a"]?.ended != nil && state.sessions["a"]?.pid == nil)
        // Ending it again, or finding its process gone, changes nothing.
        let again = state.apply(.end(session: "a"))
        let pruned = state.prune(isAlive: { $0 == 8 })
        #expect(!again && !pruned)
        #expect(state.slots[0] == .idle)
    }

    @Test func aSessionCanBeForgottenByHand() throws {
        #expect(try Command.parse(#"{"op":"forget","session":"a"}"#) == .forget(session: "a"))
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: nil, cwd: nil, host: app("aaaa")))
        state.apply(.end(session: "a"))
        state.apply(.forget(session: "a"))
        #expect(state.slots[0] == .off && state.sessions.isEmpty)
    }

    @Test func whatASessionFinishedStaysUnreadAfterItEnds() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .done, pid: nil, cwd: nil, host: app("aaaa")))
        state.apply(.end(session: "a"))
        #expect(state.slots[0] == .done)
        let seen = state.acknowledge(slot: 0)
        #expect(seen)
        #expect(state.slots[0] == .idle && state.owner(of: 0)?.id == "a")
    }

    @Test func aSessionWithNoPlaceToOpenAgainGivesItsKeyUp() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: 7, cwd: nil))
        state.apply(.end(session: "a"))
        #expect(state.slots[0] == .off && state.sessions.isEmpty)
    }

    @Test func aSessionThatComesBackIsOnItsKeyAgain() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: 7, cwd: nil, host: app("aaaa")))
        state.apply(.report(session: "b", status: .working, pid: 8, cwd: nil, host: app("bbbb")))
        state.apply(.end(session: "a"))
        state.apply(.report(session: "a", status: .working, pid: 9, cwd: nil, host: app("aaaa")))
        #expect(state.sessions["a"]?.slot == 0 && state.sessions["a"]?.ended == nil && state.slots[0] == .working)
        let notes = state.takeNotes()
        #expect(notes.contains("session a is back on key 1"))
    }

    @Test func aNewSessionInTheSameClaudeAppSessionTakesOverTheKey() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: 7, cwd: nil, host: app("aaaa")))
        state.apply(.report(session: "b", status: .working, pid: 8, cwd: nil, host: app("bbbb")))
        state.apply(.end(session: "b"))
        state.apply(.report(session: "c", status: .working, pid: 9, cwd: nil, host: app("bbbb")))
        #expect(state.sessions["c"]?.slot == 1 && state.sessions["b"] == nil && state.slots[1] == .working)
        // The other way round: the new one shows up first, so the old one has nothing to keep.
        state.apply(.report(session: "d", status: .working, pid: 10, cwd: nil, host: app("aaaa")))
        state.apply(.end(session: "a"))
        #expect(state.sessions["a"] == nil && state.slots[0] == .off && state.sessions["d"]?.slot == 2)
    }

    @Test func aNewSessionTakesTheKeyOfOneThatEnded() {
        var state = BridgeState()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for n in 1 ... 6 {
            state.apply(.report(session: "s\(n)", status: n == 3 ? .done : .working, pid: nil, cwd: nil, host: app("s\(n)")))
        }
        state.apply(.end(session: "s3"), at: start)                              // unread: gives up last
        state.apply(.end(session: "s5"), at: start.addingTimeInterval(10))
        state.apply(.end(session: "s2"), at: start.addingTimeInterval(20))
        state.apply(.report(session: "new1", status: .working, pid: nil, cwd: nil, host: app("n1")))
        #expect(state.sessions["new1"]?.slot == 4 && state.sessions["s5"] == nil)
        state.apply(.report(session: "new2", status: .working, pid: nil, cwd: nil, host: app("n2")))
        #expect(state.sessions["new2"]?.slot == 1 && state.sessions["s2"] == nil)
        // What is left is as urgent as the newcomer, or more: an unread result stays.
        state.apply(.report(session: "new3", status: .working, pid: nil, cwd: nil, host: app("n3")))
        #expect(state.sessions["new3"]?.slot == nil && state.sessions["s3"]?.slot == 2)
        // A session that ends while another waits hands its key over at once.
        state.apply(.end(session: "s1"))
        #expect(state.sessions["new3"]?.slot == 0 && state.sessions["s1"] == nil)
    }

    @Test func anEndedSessionIsForgottenAfterAWhile() {
        var state = BridgeState()
        let start = Date(timeIntervalSince1970: 1_000_000)
        // Left alone, a key remembers its session until another takes it.
        state.apply(.report(session: "a", status: .working, pid: nil, cwd: nil, host: app("aaaa")))
        state.apply(.end(session: "a"), at: start)
        let never = state.prune(isAlive: { _ in true }, at: start.addingTimeInterval(365 * 24 * 3600))
        #expect(!never && state.slots[0] == .idle)
        // With a limit, it lets go when the time is up.
        state.rememberSeconds = 24 * 3600
        let early = state.prune(isAlive: { _ in true }, at: start.addingTimeInterval(23 * 3600))
        #expect(!early && state.slots[0] == .idle)
        let late = state.prune(isAlive: { _ in true }, at: start.addingTimeInterval(24 * 3600))
        #expect(late)
        #expect(state.slots[0] == .off && state.sessions.isEmpty)
    }

    @Test func rememberingEndedSessionsCanBeTurnedOff() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: nil, cwd: nil, host: app("aaaa")))
        state.apply(.report(session: "b", status: .working, pid: nil, cwd: nil, host: app("bbbb")))
        state.apply(.end(session: "a"))
        state.rememberSeconds = 0
        #expect(state.slots[0] == .off && state.sessions["a"] == nil)
        state.apply(.end(session: "b"))
        #expect(state.slots[1] == .off && state.sessions.isEmpty)
    }

    @Test func aProcessFoundGoneCountsAsAnEnd() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .needsYou, pid: 7, cwd: nil, host: app("aaaa")))
        let changed = state.prune(isAlive: { _ in false })
        #expect(changed)
        #expect(state.slots[0] == .idle && state.sessions["a"]?.ended != nil)
    }

    @Test func keysComeBackAfterARestart() {
        var state = BridgeState()
        let saved = Date(timeIntervalSince1970: 1_763_432_000)
        state.apply(.report(session: "live", status: .working, pid: 7, cwd: "/proj", host: app("live"), transcript: "/t/live.jsonl"))
        state.apply(.report(session: "dead", status: .needsYou, pid: 8, cwd: nil, host: app("dead")))
        state.apply(.report(session: "term", status: .idle, pid: 9, cwd: nil))
        state.apply(.report(session: "old", status: .done, pid: 10, cwd: nil, host: app("old")))
        state.apply(.end(session: "old"), at: saved.addingTimeInterval(-600))
        let text = state.snapshot(at: saved)

        var back = BridgeState()
        let held = back.restore(text) { pid, when in pid == 7 && when == saved }
        #expect(held == 3)
        #expect(back.slots == [.working, .idle, .off, .done, .off, .off])
        #expect(back.sessions["live"]?.pid == 7 && back.sessions["live"]?.ended == nil)
        #expect(back.sessions["live"]?.cwd == "/proj" && back.sessions["live"]?.transcript == "/t/live.jsonl")
        #expect(back.sessions["dead"]?.ended == saved && back.sessions["dead"]?.host == app("dead"))
        #expect(back.sessions["term"] == nil)
        #expect(back.sessions["old"]?.ended == saved.addingTimeInterval(-600))
        // A session that was only presumed gone is back on its key with its next report.
        back.apply(.report(session: "dead", status: .working, pid: 8, cwd: nil, host: app("dead")))
        #expect(back.sessions["dead"]?.slot == 1 && back.slots[1] == .working)
        // New sessions fill the free keys first.
        back.apply(.report(session: "new", status: .working, pid: 11, cwd: nil, host: app("new")))
        #expect(back.sessions["new"]?.slot == 2)

        var junk = BridgeState()
        let one = junk.restore("not json") { _, _ in true }
        let two = junk.restore(#"{"version":2,"saved":1,"sessions":[]}"#) { _, _ in true }
        let three = junk.restore(#"{"version":1,"saved":1,"sessions":[{"session":"x","status":"off","slot":0},{"session":"y","status":"idle","slot":9,"host":"orca:1"}]}"#) { _, _ in true }
        #expect(one == 0 && two == 0 && three == 0)
        #expect(junk.slots.allSatisfy { $0 == .off })
    }

    @Test func readsTheSessionFromAClaudePagesAddress() {
        let id = "local_0a1b2c3d-1111-4222-8333-444455556666"
        #expect(SessionHost(page: URL(string: "https://claude.ai/epitaxy/\(id)")!) == .claudeDesktop(id))
        #expect(SessionHost(page: URL(string: "https://claude.ai/epitaxy/\(id)?tab=diff")!) == .claudeDesktop(id))
        #expect(SessionHost(page: URL(string: "https://claude.ai/epitaxy")!) == nil)
        #expect(SessionHost(page: URL(string: "https://claude.ai/epitaxy/new")!) == nil)
        #expect(SessionHost(page: URL(string: "https://claude.ai/chat/\(id)")!) == nil)
        #expect(SessionHost(page: URL(string: "file:///Applications/Claude.app/index.html")!) == nil)
    }

    @Test func findsTheKeysOfTheSessionsOnScreen() {
        var state = BridgeState()
        let a = SessionHost.claudeDesktop("local_aaaa"), b = SessionHost.claudeDesktop("local_bbbb")
        state.apply(.report(session: "one", status: .working, pid: nil, cwd: nil, host: a))
        state.apply(.report(session: "two", status: .idle, pid: nil, cwd: nil, host: b))
        state.apply(.report(session: "three", status: .idle, pid: nil, cwd: nil))
        #expect(state.slots(showing: [b]) == [1])
        #expect(state.slots(showing: [a, b]) == [0, 1])
        #expect(state.slots(showing: [.claudeDesktop("local_cccc")]).isEmpty)
        #expect(state.slots(showing: []).isEmpty)
        let lights = state.lights(Config.Lighting(), selected: state.slots(showing: [b]))
        #expect(lights[0].effect == .solid && lights[1].effect == .breath && lights[2].effect == .solid)
    }

    @Test func warnsOnceWhenTheBatteryRunsLow() {
        var watch = BatteryWatch(threshold: 20)
        #expect(watch.read(battery: 50, charging: false) == nil)
        #expect(watch.read(battery: 20, charging: false) == 20)
        #expect(watch.read(battery: 19, charging: false) == nil)
        #expect(watch.read(battery: 5, charging: nil) == nil)
    }

    @Test func staysQuietAboutTheBatteryWhileThePadCharges() {
        var watch = BatteryWatch(threshold: 20)
        #expect(watch.read(battery: 10, charging: true) == nil)
        #expect(watch.read(battery: 10, charging: false) == 10)
    }

    @Test func warnsAboutTheBatteryAgainAfterACharge() {
        var watch = BatteryWatch(threshold: 20)
        #expect(watch.read(battery: 15, charging: false) == 15)
        #expect(watch.read(battery: 16, charging: true) == nil)
        #expect(watch.read(battery: 15, charging: false) == 15)
        // A reading that wobbles around the threshold does not warn twice.
        #expect(watch.read(battery: 22, charging: false) == nil)
        #expect(watch.read(battery: 20, charging: false) == nil)
        #expect(watch.read(battery: 26, charging: false) == nil)
        #expect(watch.read(battery: 20, charging: false) == 20)
    }

    @Test func theBatteryWarningCanBeTurnedOff() {
        var watch = BatteryWatch(threshold: 0)
        #expect(watch.read(battery: 1, charging: false) == nil)
        watch.threshold = 20
        #expect(watch.read(battery: nil, charging: false) == nil)
        #expect(watch.read(battery: 1, charging: false) == 1)
    }

    @Test func staysQuietOnOurLayer() {
        var watch = LayerWatch()
        #expect(watch.read(1) == nil)
        #expect(watch.read(1) == nil)
        #expect(watch.layer == 1)
    }

    @Test func saysWhenThePadLeavesOurLayerAndWhenItReturns() {
        var watch = LayerWatch()
        #expect(watch.read(1) == nil)
        #expect(watch.read(2) == .away(2))
        #expect(watch.read(2) == nil)
        #expect(watch.read(3) == .away(3))
        #expect(watch.read(1) == .back)
        #expect(watch.read(1) == nil)
    }

    @Test func warnsWhenThePadStartsOnAnotherLayer() {
        var watch = LayerWatch()
        #expect(watch.read(2) == .away(2))
        #expect(watch.read(1) == .back)
    }

    @Test func ignoresAMissingLayerAndForgetsOnReset() {
        var watch = LayerWatch()
        #expect(watch.read(2) == .away(2))
        #expect(watch.read(nil) == nil)
        #expect(watch.layer == 2)
        watch.reset()
        #expect(watch.layer == nil)
        // A pad that comes back on our layer needs no "back" message: the warning was for the old connection.
        #expect(watch.read(1) == nil)
    }

    @Test func stateCarriesLayerAndBatteryOnlyWithAPad() {
        let status = DeviceStatus(JSONValue.parse(#"{"version":"v0.6.1","profile_index":0,"layer_index":2,"battery":100,"is_charging":true}"#)!)
        let info = PadInfo(productID: 0x8360, model: "Codex Micro", transport: "USB", product: nil, usagePairs: [],
                           maxInputReport: 64, maxOutputReport: 64)
        let with = Reply.state(BridgeState(), pad: info, status: status)
        #expect(with.contains(#""transport":"USB","layer":2,"battery":100,"charging":true}"#))
        #expect(with.contains(#""model":"Codex Micro","firmware":"v0.6.1","transport":"USB""#))
        let without = Reply.state(BridgeState(), pad: nil, status: status)
        #expect(!without.contains("layer") && !without.contains("battery") && !without.contains("firmware"))
    }

    @Test func stateSaysWhatMacOSAllowsWhenAsked() {
        let access = Reply.Access(inputMonitoring: .denied, accessibility: true)
        #expect(Reply.state(BridgeState(), pad: nil, access: access)
            .hasSuffix(#""sessions":[],"inputMonitoring":"denied","accessibility":true}"#))
        #expect(!Reply.state(BridgeState(), pad: nil).contains("accessibility"))
    }
}

@Suite struct LightingTests {
    @Test func colorsMatchChatGPT() {
        #expect(AgentStatus.working.color == 0x304FFE)
        #expect(AgentStatus.needsYou.color == 0xFF6D00)
        #expect(AgentStatus.idle.color == 0xFFFFFF)
        #expect(AgentStatus.done.color == 0x00FF4C)
        #expect(AgentStatus.failed.color == 0xFF0033)
    }

    @Test func offIsFullyDark() {
        #expect(AgentStatus.off.light(slot: 3).json.serialized == #"{"id":3,"c":0,"b":0,"e":0,"s":0,"sk":0,"sa":0}"#)
    }

    @Test func partialSlotOmitsUnsetFields() {
        #expect(SlotLight(slot: 1, brightness: 0.5).json.serialized == #"{"id":1,"b":0.5}"#)
    }

    @Test func zoneShape() {
        #expect(ZoneLight.off.json.serialized == #"{"e":0,"b":0,"s":0,"m":0,"c":0}"#)
    }
}

@Suite struct ControlTests {
    @Test func parsesCommands() throws {
        #expect(try Command.parse(#"{"op":"set","slot":2,"status":"needs-you"}"#) == .set(slot: 2, status: .needsYou))
        #expect(try Command.parse(#"{"op":"clear"}"#) == .clear)
        #expect(try Command.parse(#"{"op":"state"}"#) == .state)
        #expect(try Command.parse(#"{"op":"subscribe"}"#) == .subscribe)
    }

    @Test func rejectsBadCommands() {
        for line in ["nope", "[]", #"{"op":"fs.write"}"#, #"{"op":"set","slot":6,"status":"idle"}"#,
                     #"{"op":"set","slot":-1,"status":"idle"}"#, #"{"op":"set","slot":0,"status":"purple"}"#,
                     #"{"op":"set","slot":1.5,"status":"idle"}"#] {
            #expect(throws: Command.Invalid.self) { try Command.parse(line) }
        }
    }

    @Test func stateTracksSlots() {
        var state = BridgeState()
        let first = state.apply(.set(slot: 1, status: .working))
        let repeated = state.apply(.set(slot: 1, status: .working))
        let query = state.apply(.state)
        #expect(first && !repeated && !query)
        #expect(state.slots == [.off, .working, .off, .off, .off, .off])
        #expect(state.lights.count == 6 && state.lights[1].color == 0x304FFE)
        let cleared = state.apply(.clear)
        #expect(cleared)
        #expect(state.slots.allSatisfy { $0 == .off })
    }

    @Test func replies() {
        var state = BridgeState()
        state.apply(.set(slot: 0, status: .done))
        #expect(Reply.state(state, pad: nil) ==
            #"{"ok":true,"connected":false,"slots":["done","off","off","off","off","off"],"sessions":[]}"#)
        #expect(Reply.event(.key(name: "AG03", action: 1, agent: nil)) == #"{"event":"key","name":"AG03","action":1,"slot":3}"#)
        #expect(Reply.event(.key(name: "ENC_CC", action: 2, agent: nil)) == #"{"event":"key","name":"ENC_CC","action":2}"#)
        #expect(Reply.error("no") == #"{"ok":false,"error":"no"}"#)
    }
}

@Suite @MainActor struct SocketTests {
    @Test func servesLinesAndBroadcasts() async throws {
        let dir = NSTemporaryDirectory() + "mb-\(UUID().uuidString.prefix(8))"
        let path = dir + "/daemon.sock"
        let server = try SocketServer(directory: dir, socket: path)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        server.onLine = { client, line in
            if line == "sub" { client.subscribed = true }
            client.send("echo " + line)
        }
        #expect(throws: SocketError.self) { _ = try SocketServer(directory: dir, socket: path) }

        var attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        attributes = try FileManager.default.attributesOfItem(atPath: dir)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)

        let reply = await Task.detached {
            var lines: [String] = []
            try? SocketClient.send("hello", to: path) { lines.append($0); return false }
            return lines
        }.value
        #expect(reply == ["echo hello"])

        let stream = Task.detached {
            var lines: [String] = []
            try? SocketClient.send("sub", to: path) { lines.append($0); return lines.count < 2 }
            return lines
        }
        while !server.clients.contains(where: \.subscribed) { try await Task.sleep(for: .milliseconds(5)) }
        server.broadcast("event 1")
        #expect(await stream.value == ["echo sub", "event 1"])
    }
}

@Suite struct SessionTests {
    func report(_ id: String, _ status: AgentStatus, pid: Int? = nil) -> Command {
        .report(session: id, status: status, pid: pid, cwd: nil)
    }

    @Test func parsesReportAndEnd() throws {
        #expect(try Command.parse(#"{"op":"report","session":"a","status":"working","pid":42,"cwd":"/x"}"#) ==
            .report(session: "a", status: .working, pid: 42, cwd: "/x"))
        #expect(try Command.parse(#"{"op":"report","session":"a","status":"done"}"#) ==
            .report(session: "a", status: .done, pid: nil, cwd: nil))
        #expect(try Command.parse(#"{"op":"end","session":"a"}"#) == .end(session: "a"))
        for line in [#"{"op":"report","status":"done"}"#, #"{"op":"report","session":"","status":"done"}"#,
                     #"{"op":"report","session":"a","status":"done","pid":1}"#, #"{"op":"end"}"#] {
            #expect(throws: Command.Invalid.self) { try Command.parse(line) }
        }
    }

    @Test func eachSessionGetsItsOwnKeyAndKeepsIt() {
        var state = BridgeState()
        state.apply(report("a", .working))
        state.apply(report("b", .needsYou))
        state.apply(report("a", .done))
        #expect(state.slots == [.done, .needsYou, .off, .off, .off, .off])
        #expect(state.sessions["a"]?.slot == 0 && state.sessions["b"]?.slot == 1)
    }

    @Test func endingFreesTheKeyForTheNextSession() {
        var state = BridgeState()
        state.apply(report("a", .working))
        state.apply(report("b", .working))
        state.apply(.end(session: "a"))
        #expect(state.slots[0] == .off)
        state.apply(report("c", .idle))
        #expect(state.sessions["c"]?.slot == 0 && state.sessions["b"]?.slot == 1)
        let changed = state.apply(.end(session: "nobody"))
        #expect(!changed)
    }

    @Test func seventhBusySessionWaitsThenTakesAFreedKey() {
        var state = BridgeState()
        for n in 0 ..< 6 { state.apply(report("s\(n)", .working)) }
        let changed = state.apply(report("late", .working))
        #expect(!changed && state.sessions["late"]?.slot == nil)
        state.apply(report("later", .working))
        state.apply(.end(session: "s2"))
        // Equally urgent: the latest to do something gets the key.
        #expect(state.sessions["later"]?.slot == 2 && state.slots[2] == .working)
        #expect(state.sessions["late"]?.slot == nil)
    }

    @Test func aMoreUrgentSessionTakesTheKeyOfALessUrgentOne() {
        var state = BridgeState()
        for n in 0 ..< 6 { state.apply(report("s\(n)", n == 1 || n == 4 ? .idle : .working)) }
        // s1 was heard from before s4, so s1 gives its key up.
        let changed = state.apply(report("late", .needsYou))
        #expect(changed)
        #expect(state.sessions["late"]?.slot == 1 && state.slots[1] == .needsYou)
        #expect(state.sessions["s1"]?.slot == nil && state.sessions["s4"]?.slot == 4)
        #expect(state.takeHandovers() == [BridgeState.Handover(slot: 1, from: "s1", to: "late")])
        #expect(state.takeHandovers().isEmpty)
        // A busy session outranks an idle one too.
        state.apply(report("busy", .working))
        #expect(state.sessions["busy"]?.slot == 4 && state.sessions["s4"]?.slot == nil)
        // Equals do not push each other out: the session that gave its key up waits.
        state.apply(report("s1", .working))
        #expect(state.sessions["s1"]?.slot == nil)
        // Nor does a session take the key of a more urgent one.
        state.apply(report("s4", .idle))
        #expect(state.sessions["s4"]?.slot == nil)
    }

    @Test func theLeastUrgentHolderGivesUpFirst() {
        var state = BridgeState()
        let statuses: [AgentStatus] = [.working, .done, .working, .needsYou, .idle, .working]
        for (n, status) in statuses.enumerated() { state.apply(report("s\(n)", status)) }
        // A session that needs you takes the idle key, then the busy keys (heard from longest
        // ago first), then the unread one.
        state.apply(report("n1", .needsYou))
        #expect(state.sessions["n1"]?.slot == 4)
        state.apply(report("n2", .needsYou))
        #expect(state.sessions["n2"]?.slot == 0)
        state.apply(report("n3", .needsYou))
        #expect(state.sessions["n3"]?.slot == 2)
        state.apply(report("n4", .needsYou))
        #expect(state.sessions["n4"]?.slot == 5)
        state.apply(report("n5", .needsYou))
        #expect(state.sessions["n5"]?.slot == 1)
        // Every key now needs you: the next one waits.
        state.apply(report("n6", .needsYou))
        #expect(state.sessions["n6"]?.slot == nil)
        // Those pushed out are still known and wait for a key.
        #expect(state.sessions["s1"]?.status == .done && state.sessions["s1"]?.slot == nil)
        #expect(state.slots.allSatisfy { $0 == .needsYou })
    }

    @Test func aKeyThatTurnsLessUrgentGoesToAWaitingSession() {
        var state = BridgeState()
        for n in 0 ..< 6 { state.apply(report("s\(n)", n == 3 ? .done : .needsYou)) }
        // Nobody is less urgent than a busy session: it waits.
        state.apply(report("late", .working))
        #expect(state.sessions["late"]?.slot == nil)
        // Pressing the green key marks it seen, which makes it idle.
        let seen = state.acknowledge(slot: 3)
        #expect(seen)
        #expect(state.sessions["late"]?.slot == 3 && state.slots[3] == .working && state.sessions["s3"]?.slot == nil)
        // A turn stopped by hand does the same.
        state.apply(report("later", .working))
        #expect(state.sessions["later"]?.slot == nil)
        let stopped = state.stopped("s0")
        #expect(stopped)
        #expect(state.sessions["later"]?.slot == 0 && state.slots[0] == .working)
        // And so does a session that reports idle itself.
        state.apply(report("last", .working))
        state.apply(report("s5", .idle))
        #expect(state.sessions["last"]?.slot == 5 && state.sessions["s5"]?.slot == nil)
        #expect(state.takeHandovers().map(\.slot) == [3, 0, 5])
    }

    @Test func aFreedKeyGoesToTheMostUrgentWaitingSession() {
        var state = BridgeState()
        for n in 0 ..< 6 { state.apply(report("s\(n)", .needsYou)) }
        state.apply(report("asks", .needsYou))
        state.apply(report("asksLater", .needsYou))
        // Heard from more recently than both.
        state.apply(report("busy", .working))
        state.apply(.end(session: "s2"))
        // Among those that need you, the longest wait first.
        #expect(state.sessions["asks"]?.slot == 2 && state.sessions["busy"]?.slot == nil)
        // A freed key is not a handover.
        #expect(state.takeHandovers().isEmpty)
    }

    @Test func theTakeoverCanBeTurnedOff() {
        var state = BridgeState()
        state.urgentFirst = false
        for n in 0 ..< 6 { state.apply(report("s\(n)", .idle)) }
        state.apply(report("late", .needsYou))
        #expect(state.sessions["late"]?.slot == nil && state.takeHandovers().isEmpty)
        // Turning it on settles the keys at once.
        state.urgentFirst = true
        #expect(state.sessions["late"]?.slot == 0 && state.slots[0] == .needsYou)
    }

    @Test func actingOnTheSessionOnScreenMarksItRead() {
        var state = BridgeState()
        let a = SessionHost.claudeDesktop("local_aaaa"), c = SessionHost.claudeDesktop("local_cccc")
        state.apply(.report(session: "a", status: .done, pid: nil, cwd: nil, host: a))
        state.apply(.report(session: "b", status: .failed, pid: nil, cwd: nil, host: .claudeDesktop("local_bbbb")))
        state.apply(.report(session: "c", status: .working, pid: nil, cwd: nil, host: c))
        let read = state.acknowledge(showing: [a, c])
        #expect(read == [0])
        #expect(state.slots == [.idle, .failed, .working, .off, .off, .off])
        let again = state.acknowledge(showing: [a])
        #expect(again.isEmpty)
    }

    @Test func theSessionOnScreenAndAKeyJustPressedKeepTheirKeys() {
        var state = BridgeState()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for n in 0 ..< 6 {
            state.apply(.report(session: "s\(n)", status: n < 2 ? .idle : .needsYou, pid: nil, cwd: nil,
                                host: .claudeDesktop("local_s\(n)")), at: start)
        }
        state.onScreen = [.claudeDesktop("local_s0")]
        state.touch(slot: 1, at: start)
        // Both idle keys are spoken for: the newcomer waits.
        state.apply(report("late", .working), at: start.addingTimeInterval(1))
        #expect(state.sessions["late"]?.slot == nil)
        // The press wears off after 5 seconds.
        let early = state.rebalance(at: start.addingTimeInterval(4))
        #expect(!early && state.sessions["late"]?.slot == nil)
        let worn = state.rebalance(at: start.addingTimeInterval(5))
        #expect(worn && state.sessions["late"]?.slot == 1)
        // The session on screen gives its key up once it leaves the screen.
        state.apply(report("later", .working), at: start.addingTimeInterval(6))
        #expect(state.sessions["later"]?.slot == nil)
        state.onScreen = []
        #expect(state.sessions["later"]?.slot == 0 && state.sessions["s0"]?.slot == nil)
    }

    @Test func pressingAKeyMarksDoneAsSeen() {
        var state = BridgeState()
        state.apply(report("a", .done))
        state.apply(report("b", .working))
        let done = state.acknowledge(slot: 0)
        #expect(done)
        #expect(state.slots[0] == .idle && state.sessions["a"]?.status == .idle)
        let working = state.acknowledge(slot: 1)
        let empty = state.acknowledge(slot: 5)
        let outOfRange = state.acknowledge(slot: 9)
        #expect(!working && !empty && !outOfRange)
    }

    @Test func prunesSessionsWhoseProcessIsGone() {
        var state = BridgeState()
        state.apply(report("live", .working, pid: 100))
        state.apply(report("dead", .working, pid: 200))
        state.apply(report("unknown", .working))
        let first = state.prune { $0 == 100 }
        #expect(first)
        #expect(state.slots == [.working, .off, .working, .off, .off, .off])
        #expect(state.sessions["dead"] == nil)
        let second = state.prune { $0 == 100 }
        #expect(!second)
    }

    @Test func clearForgetsSessions() {
        var state = BridgeState()
        state.apply(report("a", .working))
        state.apply(.clear)
        #expect(state.sessions.isEmpty && state.slots.allSatisfy { $0 == .off })
    }

    @Test func stateReplyListsSessions() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: 42, cwd: "/x"))
        #expect(Reply.state(state, pad: nil) ==
            #"{"ok":true,"connected":false,"slots":["working","off","off","off","off","off"],"sessions":[{"slot":0,"session":"a","status":"working","cwd":"/x","pid":42}]}"#)
    }
}

@Suite struct SessionHostTests {
    @Test func acceptsOnlyPlainIds() {
        #expect(SessionHost("claude:local_0a1b2c3d-1111-4222-8333-444455556666")
            == .claudeDesktop("local_0a1b2c3d-1111-4222-8333-444455556666"))
        #expect(SessionHost("claude:local_abc")?.description == "claude:local_abc")
        // A chat in Orca, by Orca's session ID.
        #expect(SessionHost("orca:0a1b2c3d-1111-4222-8333-444455556666") == .orcaChat("0a1b2c3d-1111-4222-8333-444455556666"))
        #expect(SessionHost("orca:0a1b2c3d-1111")?.description == "orca:0a1b2c3d-1111")
        let long = String(repeating: "a", count: 65)
        for bad in ["", "claude", "claude:", "claude:local_", "claude:abc", "claude:local_a b", "claude:local_a&x=1",
                    "claude:local_a_b", "claude:local_\(long)", "claude:local_a;rm", "claude:local_$(x)",
                    "claude:local_a/b", "orca:", "orca:a b", "orca:a/b", "orca:$(x)", "orca:\(long)", "ghostty:term_a", "claude:local_é"] {
            #expect(SessionHost(bad) == nil, "\(bad)")
        }
    }

    @Test func aSessionKeepsItsHost() throws {
        var state = BridgeState()
        state.apply(try Command.parse(#"{"op":"report","session":"a","status":"working","host":"claude:local_abc"}"#))
        // A later report without a host does not forget it.
        state.apply(.report(session: "a", status: .done, pid: 42, cwd: nil))
        #expect(state.owner(of: 0)?.host == .claudeDesktop("local_abc"))
        #expect(Reply.state(state, pad: nil).contains(#""pid":42,"host":"claude:local_abc"}"#))
        for bad in ["claude:local_a b", "orca:a b", "ghostty:term_abc"] {
            #expect(throws: Command.Invalid.self, "\(bad)") {
                try Command.parse(#"{"op":"report","session":"a","status":"working","host":""# + bad + "\"}")
            }
        }
    }
}

@Suite struct ClaudeHookTests {
    func payload(_ event: String, _ extra: String = "") -> JSONValue {
        JSONValue.parse(#"{"session_id":"abc","cwd":"/proj","hook_event_name":""# + event + "\"" + extra + "}")!
    }

    @Test func mapsEventsToStatus() {
        #expect(ClaudeHook.status(for: payload("SessionStart", #","source":"startup""#)) == .idle)
        #expect(ClaudeHook.status(for: payload("SessionStart", #","source":"compact""#)) == nil)
        #expect(ClaudeHook.status(for: payload("UserPromptSubmit")) == .working)
        #expect(ClaudeHook.status(for: payload("PreToolUse", #","tool_name":"Bash""#)) == .working)
        #expect(ClaudeHook.status(for: payload("PreToolUse", #","tool_name":"AskUserQuestion""#)) == .needsYou)
        #expect(ClaudeHook.status(for: payload("PermissionRequest")) == .needsYou)
        #expect(ClaudeHook.status(for: payload("Elicitation")) == .needsYou)
        #expect(ClaudeHook.status(for: payload("PostToolUse")) == .working)
        #expect(ClaudeHook.status(for: payload("Stop")) == .done)
        #expect(ClaudeHook.status(for: payload("StopFailure")) == .failed)
        #expect(ClaudeHook.status(for: payload("SessionEnd")) == .off)
        #expect(ClaudeHook.status(for: payload("SubagentStop")) == nil)
    }

    @Test func buildsDaemonRequests() throws {
        let request = try #require(ClaudeHook.request(for: payload("UserPromptSubmit"), pid: 77))
        #expect(request == #"{"op":"report","session":"abc","status":"working","pid":77,"cwd":"/proj"}"#)
        #expect(try Command.parse(request) == .report(session: "abc", status: .working, pid: 77, cwd: "/proj"))
        #expect(ClaudeHook.request(for: payload("SessionEnd"), pid: 77) == #"{"op":"end","session":"abc"}"#)
        #expect(ClaudeHook.request(for: payload("SubagentStop"), pid: 77) == nil)
        #expect(ClaudeHook.request(for: JSONValue.parse(#"{"hook_event_name":"Stop"}"#)!, pid: nil) == nil)
    }

    @Test func reportsWhereTheSessionLives() throws {
        let desktop = ["CLAUDE_CODE_HOST_SESSION_ID": "local_0a1b-c2", "PATH": "/bin"]
        let request = try #require(ClaudeHook.request(for: payload("Stop"), pid: 77, environment: desktop))
        #expect(request ==
            #"{"op":"report","session":"abc","status":"done","pid":77,"cwd":"/proj","host":"claude:local_0a1b-c2"}"#)
        #expect(try Command.parse(request) ==
            .report(session: "abc", status: .done, pid: 77, cwd: "/proj", host: .claudeDesktop("local_0a1b-c2")))
        // An id that is not a plain id is left out; the status still goes through.
        let odd = ["CLAUDE_CODE_HOST_SESSION_ID": "local_a&b=c"]
        #expect(ClaudeHook.request(for: payload("Stop"), pid: nil, environment: odd)?.contains("host") == false)
        #expect(ClaudeHook.request(for: payload("Stop"), pid: nil, environment: ["HOME": "/x"])?
            .contains("host") == false)
    }

    @Test func staysOutOfOrcaTerminals() {
        // Orca sets this in every terminal it opens. A session there sends nothing at all.
        let orca = ["ORCA_TERMINAL_HANDLE": "term_8aed_a6-d3", "PATH": "/bin"]
        for event in ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "SessionEnd"] {
            #expect(ClaudeHook.request(for: payload(event), pid: 77, environment: orca) == nil, "\(event)")
        }
        // A Claude app session is still reported, whatever else its environment holds.
        let desktop = ["CLAUDE_CODE_HOST_SESSION_ID": "local_0a1b-c2", "ORCA_TERMINAL_HANDLE": "term_x"]
        #expect(ClaudeHook.request(for: payload("Stop"), pid: nil, environment: desktop)?
            .hasSuffix(#""host":"claude:local_0a1b-c2"}"#) == true)
        #expect(ClaudeHook.request(for: payload("Stop"), pid: nil, environment: ["ORCA_TERMINAL_HANDLE": ""]) != nil)
    }

    @Test func recognisesClaudeCodeProcesses() {
        #expect(ProcessTree.isClaudeCode(path: "/Users/x/Library/Application Support/Claude/claude-code/2.1.321/abc/claude.app/Contents/MacOS/claude"))
        #expect(ProcessTree.isClaudeCode(path: "/Users/x/.local/share/claude/versions/2.1.321"))
        #expect(!ProcessTree.isClaudeCode(path: "/Applications/Claude.app/Contents/MacOS/Claude"))
        #expect(!ProcessTree.isClaudeCode(path: "/bin/zsh"))
        #expect(ProcessTree.isAlive(Int(getpid())))
    }
}

@Suite struct PinTests {
    private func report(_ id: String, _ status: AgentStatus, host: String? = nil, pid: Int? = nil) -> Command {
        .report(session: id, status: status, pid: pid, cwd: nil, host: host.flatMap { SessionHost("claude:local_" + $0) })
    }

    /// Six sessions, s0 to s5, on keys 1 to 6.
    private func full(_ status: AgentStatus = .idle) -> BridgeState {
        var state = BridgeState()
        for n in 0 ..< 6 { state.apply(report("s\(n)", status)) }
        return state
    }

    @Test func parsesPinAndUnpin() throws {
        #expect(try Command.parse(#"{"op":"pin","session":"a"}"#) == .pin(session: "a"))
        #expect(try Command.parse(#"{"op":"pin","session":"a","slot":5}"#) == .pin(session: "a", slot: 5))
        #expect(try Command.parse(#"{"op":"pin","session":"a","slot":null}"#) == .pin(session: "a"))
        #expect(try Command.parse(#"{"op":"unpin","session":"a"}"#) == .unpin(session: "a"))
        for line in [#"{"op":"pin"}"#, #"{"op":"pin","session":"a","slot":6}"#, #"{"op":"pin","session":"a","slot":"two"}"#,
                     #"{"op":"unpin"}"#] {
            #expect(throws: Command.Invalid.self) { try Command.parse(line) }
        }
    }

    @Test func aPinnedSessionKeepsItsKeyFromAMoreUrgentOne() {
        var state = full()
        let pinned = state.pin("s0")
        #expect(pinned)
        state.apply(report("late", .needsYou))
        // s0 was heard from longest ago and would give up first. Pinned, it stays and s1 goes.
        #expect(state.sessions["s0"]?.slot == 0 && state.sessions["s0"]?.pinned == true)
        #expect(state.sessions["late"]?.slot == 1 && state.sessions["s1"]?.slot == nil)
        #expect(state.pinnedSlots == [0])
        #expect(state.takeNotes().contains("session s0 is pinned to key 1"))
    }

    @Test func unpinningLetsTheKeyGo() {
        var state = full()
        for n in 0 ..< 6 { state.pin("s\(n)") }
        state.apply(report("late", .needsYou))
        #expect(state.sessions["late"]?.slot == nil)
        let unpinned = state.unpin("s3")
        #expect(unpinned)
        #expect(state.sessions["late"]?.slot == 3 && state.sessions["s3"]?.slot == nil)
        let again = state.unpin("s3")
        let nobody = state.unpin("nobody")
        #expect(!again && !nobody)
    }

    @Test func pinningToAnotherKeyTradesPlaces() {
        var state = BridgeState()
        state.apply(report("a", .working))
        state.apply(report("b", .done))
        state.apply(report("c", .idle))
        state.pin("a", to: 2)
        #expect(state.sessions["a"]?.slot == 2 && state.sessions["c"]?.slot == 0)
        #expect(state.slots == [.idle, .done, .working, .off, .off, .off])
        #expect(state.sessions["c"]?.pinned == false)
        // To a free key: the key it leaves goes dark.
        state.pin("b", to: 5)
        #expect(state.slots == [.idle, .off, .working, .off, .off, .done])
        // A pinned session that trades places keeps its pin.
        state.pin("c", to: 2)
        #expect(state.sessions["a"]?.slot == 0 && state.sessions["a"]?.pinned == true)
        #expect(state.sessions["c"]?.slot == 2)
        #expect(state.pinnedSlots == [0, 2, 5])
        let offThePad = state.pin("a", to: 6)
        let nobody = state.pin("nobody")
        #expect(!offThePad && !nobody)
        #expect(state.sessions["a"]?.slot == 0)
    }

    @Test func pinningASessionWhereItIsChangesNoLight() {
        var state = full(.working)
        let changed = state.apply(.pin(session: "s2"))
        #expect(!changed && state.sessions["s2"]?.pinned == true && state.sessions["s2"]?.slot == 2)
        let moved = state.apply(.pin(session: "s2", slot: 0))
        #expect(!moved) // both are working: the two keys show the same
        #expect(state.sessions["s2"]?.slot == 0 && state.sessions["s0"]?.slot == 2)
    }

    @Test func aWaitingSessionCanBePinned() {
        var state = full(.working)
        state.apply(report("late", .working))
        #expect(state.sessions["late"]?.slot == nil)
        state.pin("s0")
        let pinned = state.pin("late")
        #expect(pinned)
        // s1 is the holder heard from longest ago among those not pinned.
        #expect(state.sessions["late"]?.slot == 1 && state.sessions["s1"]?.slot == nil)
        // Onto a named key whose session is pinned: that one waits and loses its pin.
        state.apply(report("later", .working))
        state.pin("later", to: 0)
        #expect(state.sessions["later"]?.slot == 0 && state.sessions["later"]?.pinned == true)
        #expect(state.sessions["s0"]?.slot == nil && state.sessions["s0"]?.pinned == false)
    }

    @Test func withEveryKeyPinnedAWaitingSessionNeedsAKeyNamed() {
        var state = full()
        for n in 0 ..< 6 { state.pin("s\(n)") }
        state.apply(report("late", .needsYou))
        let pinned = state.pin("late")
        #expect(!pinned)
        #expect(state.sessions["late"]?.slot == nil && state.sessions["late"]?.pinned == false)
        state.pin("late", to: 4)
        #expect(state.sessions["late"]?.slot == 4 && state.sessions["s4"]?.slot == nil)
    }

    @Test func aPinnedSessionThatEndedKeepsItsKey() {
        var state = BridgeState()
        state.rememberSeconds = 3600
        let start = Date(timeIntervalSince1970: 1_000_000)
        state.apply(report("a", .working, host: "one"), at: start)
        state.apply(report("b", .working, host: "two"), at: start)
        state.pin("a")
        state.apply(.end(session: "a"), at: start)
        state.apply(.end(session: "b"), at: start)
        // Two hours on, the one that is not pinned is forgotten.
        state.prune(isAlive: { _ in true }, at: start.addingTimeInterval(7200))
        #expect(state.sessions["a"]?.slot == 0 && state.sessions["b"] == nil)
        // Even with ended sessions not remembered at all.
        state.rememberSeconds = 0
        #expect(state.sessions["a"]?.slot == 0 && state.sessions["a"]?.ended != nil)
        // A session that needs its person finds five keys held by sessions that need theirs, and
        // one by an ended session. Only the pin keeps that one.
        for n in 0 ..< 5 { state.apply(report("s\(n)", .needsYou)) }
        state.apply(report("late", .needsYou))
        #expect(state.sessions["a"]?.slot == 0 && state.sessions["late"]?.slot == nil)
        state.unpin("a")
        #expect(state.sessions["a"] == nil && state.sessions["late"]?.slot == 0)
    }

    @Test func aPinnedSessionThatCannotBeOpenedAgainFreesItsKey() {
        // A session in a terminal: once it ends there is nothing for a press to open.
        var state = BridgeState()
        state.apply(report("t", .working))
        state.pin("t")
        state.apply(.end(session: "t"))
        #expect(state.sessions["t"] == nil && state.slots[0] == .off && state.pinnedSlots.isEmpty)
    }

    @Test func thePinStaysWithTheClaudeAppSession() {
        var state = BridgeState()
        state.apply(report("x", .idle))
        state.apply(report("old", .working, host: "one"))
        state.pin("old")
        // The Claude Code session in it ends and a new one starts: same key, still pinned.
        state.apply(.end(session: "old"))
        state.apply(report("new", .working, host: "one"))
        #expect(state.sessions["old"] == nil)
        #expect(state.sessions["new"]?.slot == 1 && state.sessions["new"]?.pinned == true)
        // The next one starts before this one ends: it moves over when this one ends.
        state.apply(report("newer", .working, host: "one"))
        #expect(state.sessions["newer"]?.slot == 2 && state.sessions["newer"]?.pinned == false)
        state.apply(.end(session: "new"))
        #expect(state.sessions["new"] == nil)
        #expect(state.sessions["newer"]?.slot == 1 && state.sessions["newer"]?.pinned == true)
        #expect(state.slots == [.idle, .working, .off, .off, .off, .off])
    }

    @Test func withUrgencyOffAPinnedEndedSessionStillKeepsItsKey() {
        var state = BridgeState()
        state.urgentFirst = false
        for n in 0 ..< 6 { state.apply(report("s\(n)", .working, host: "h\(n)")) }
        state.pin("s0")
        state.apply(.end(session: "s0"))
        state.apply(.end(session: "s1"))
        state.apply(report("late", .working))
        #expect(state.sessions["late"]?.slot == 1 && state.sessions["s1"] == nil)
        #expect(state.sessions["s0"]?.slot == 0 && state.sessions["s0"]?.pinned == true)
    }

    @Test func forgettingAPinnedSessionFreesItsKey() {
        var state = full()
        state.pin("s2")
        state.apply(report("late", .idle))
        state.apply(.forget(session: "s2"))
        #expect(state.sessions["s2"] == nil && state.sessions["late"]?.slot == 2)
        #expect(state.sessions["late"]?.pinned == false && state.pinnedSlots.isEmpty)
    }

    @Test func pinsComeBackAfterARestart() {
        var state = BridgeState()
        state.apply(report("a", .working, host: "one", pid: 100))
        state.apply(report("b", .idle, pid: 101))
        state.pin("a", to: 4)
        let text = state.snapshot()

        var back = BridgeState()
        back.restore(text) { _, _ in true }
        #expect(back.sessions["a"]?.slot == 4 && back.sessions["a"]?.pinned == true)
        #expect(back.sessions["b"]?.slot == 1 && back.sessions["b"]?.pinned == false)
        #expect(back.pinnedSlots == [4])

        // Its process did not survive: it counts as ended and keeps the key and the pin.
        var later = BridgeState()
        later.restore(text) { _, _ in false }
        #expect(later.sessions["a"]?.slot == 4 && later.sessions["a"]?.pinned == true && later.sessions["a"]?.ended != nil)
        #expect(later.sessions["b"] == nil)
    }

    @Test func stateSaysWhichSessionsArePinned() throws {
        var state = BridgeState()
        state.apply(report("a", .working))
        state.apply(report("b", .working))
        state.pin("b")
        let reply = try #require(JSONValue.parse(Reply.state(state, pad: nil)))
        guard case let .array(sessions)? = reply["sessions"] else {
            Issue.record("no sessions in the reply")
            return
        }
        #expect(sessions.count == 2)
        #expect(sessions[0]["pinned"] == nil && sessions[1]["pinned"]?.bool == true)
    }

    @Test func pinIsAnActionAKeyCanBeBoundTo() throws {
        #expect(Action.parse("pin") == .pin)
        #expect(Action.parse("pin:3") == nil)
        #expect(Action.pin.description == "pin")
        #expect(Action.pin.plainWords == "Pin the session to its key, or unpin it")
        let config = try Config.parse(#"{"agentKeys": {"press": ["ack", "jump"], "doubleTap": "pin"}}"#)
        #expect(config.actions(for: "AG", "doubleTap") == [.pin])
        #expect(config.hasDoubleTap("AG"))
        #expect(!Config.builtIn.hasDoubleTap("AG"))
    }
}
