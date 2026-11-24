import Foundation
import MicroKit
import Testing
@testable import MicroUI

/// The window's changes to the config file, on files in a folder made for each test.
@MainActor @Suite struct BridgeModelTests {
    private func model(config text: String? = Config.defaultFileText) throws -> BridgeModel {
        let folder = NSTemporaryDirectory() + "micro-ui-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        var files = BridgeFiles()
        files.config = folder + "/config.json"
        files.socket = folder + "/none.sock"
        files.log = folder + "/none.log"
        files.claudeSettings = folder + "/settings.json"
        if let text { try text.write(toFile: files.config, atomically: true, encoding: .utf8) }
        let model = BridgeModel(files: files)
        model.refresh()
        return model
    }

    private func onDisk(_ model: BridgeModel) -> String? {
        FileManager.default.contents(atPath: model.files.config).map { String(decoding: $0, as: UTF8.self) }
    }

    private func actions(_ texts: String...) -> [Action] {
        texts.compactMap(Action.parse)
    }

    @Test func aKeyTakesACommandAndGoesBack() throws {
        let model = try model()
        #expect(model.keycap("ACT06").cap == .command("FAST"))
        #expect(model.keycap("ACT06").isDefault)
        #expect(model.legend("ACT06") == "Fast")
        #expect(model.face("ACT06") == .symbol("bolt"))

        model.setKeycap("ACT06", to: "REJ")
        #expect(model.keycap("ACT06").cap == .command("REJ"))
        #expect(!model.keycap("ACT06").isDefault)
        #expect(model.legend("ACT06") == "Decline")
        #expect(model.face("ACT06") == .symbol("xmark.circle"))
        #expect(model.does("ACT06", "press").terminal == actions("key:escape"))
        #expect(model.notice == nil)

        model.save()
        let saved = try Config.parse(try #require(onDisk(model)))
        #expect(saved == model.config)
        #expect(saved.actions(for: "ACT06", "press") == actions("key:escape"))
        // Every other control is as it was.
        var expected = Config.builtIn
        expected.bindings = expected.bindings.filter { !$0.key.hasPrefix("ACT06.") }
        #expect(saved.bindings.filter { !$0.key.hasPrefix("ACT06.") } == expected.bindings)
        #expect(saved.commands == Config.builtIn.commands)

        model.resetKey("ACT06")
        #expect(model.keycap("ACT06").cap == .command("FAST"))
        #expect(model.keycap("ACT06").isDefault)
        #expect(model.config == Config.builtIn)
    }

    @Test func theFirstSaveKeepsTheFileAsItWas() throws {
        let model = try model()
        let backup = model.files.config + ".before-app"
        #expect(!FileManager.default.fileExists(atPath: backup))
        model.setKeycap("ACT12", to: "NEW")
        model.save()
        #expect(FileManager.default.contents(atPath: backup) == Data(Config.defaultFileText.utf8))
        // A later save leaves the first copy alone.
        model.setKeycap("ACT12", to: "FAST")
        model.save()
        #expect(FileManager.default.contents(atPath: backup) == Data(Config.defaultFileText.utf8))
        #expect(try Config.parse(try #require(onDisk(model))).actions(for: "ACT12", "press") == actions("text:/fast\n"))
    }

    @Test func aKeyCanDoNothing() throws {
        let model = try model()
        model.setKeycap("ACT12", to: nil)
        #expect(model.keycap("ACT12").cap == .nothing)
        #expect(model.legend("ACT12") == "")
        #expect(model.face("ACT12") == .blank)
        #expect(model.does("ACT12", "press").claude.isEmpty)
        #expect(model.does("ACT12", "press").terminal.isEmpty)
    }

    @Test func agentKeySwitchesKeepTheOtherTriggers() throws {
        let model = try model()
        #expect(model.trigger("hold", of: "agentKeys") == .string("forget"))
        #expect(model.trigger("empty", of: "agentKeys") == nil)
        #expect(model.sectionIsDefault("agentKeys"))

        model.setTrigger("hold", of: "agentKeys", to: nil)
        #expect(model.config.actions(for: "AG", "hold").isEmpty)
        #expect(model.config.actions(for: "AG", "press") == actions("ack", "jump", "pane:chat"))
        #expect(!model.sectionIsDefault("agentKeys"))

        model.setTrigger("empty", of: "agentKeys", to: .string("open:claude://code/new"))
        #expect(model.config.actions(for: "AG", "empty") == actions("open:claude://code/new"))
        #expect(model.config.actions(for: "AG", "press") == actions("ack", "jump", "pane:chat"))

        model.set(nil, at: ["agentKeys"])
        #expect(model.config.actions(for: "AG", "hold") == actions("forget"))
        #expect(model.config.actions(for: "AG", "empty").isEmpty)
    }

    @Test func swappingTheDialKeepsItsPressAndHold() throws {
        let model = try model()
        let before = model.config
        model.swapDial()
        #expect(model.config.bindings["DIAL.cw"] == before.bindings["DIAL.ccw"])
        #expect(model.config.bindings["DIAL.ccw"] == before.bindings["DIAL.cw"])
        #expect(model.config.bindings["DIAL.press"] == before.bindings["DIAL.press"])
        #expect(model.config.bindings["DIAL.hold"] == before.bindings["DIAL.hold"])
        model.swapDial()
        #expect(model.config == before)
        #expect(model.sectionIsDefault("dial"))
    }

    @Test func aStickDirectionChangesAlone() throws {
        let model = try model()
        model.setTrigger("up", of: "stick", to: .string("cmd:NEW"))
        #expect(model.config.bindings["STICK.up"] == actions("cmd:NEW"))
        #expect(model.config.bindings["STICK.left"] == Config.builtIn.bindings["STICK.left"])
        model.setTrigger("down", of: "stick", to: nil)
        #expect(model.config.bindings["STICK.down"] == nil)
        #expect(model.config.bindings["STICK.right"] == Config.builtIn.bindings["STICK.right"])
    }

    @Test func settingsAndColorsAreWritten() throws {
        let model = try model(config: "{}")
        #expect(model.config == Config.builtIn)
        model.set(.bool(false), at: ["urgentFirst"])
        model.set(.string("always"), at: ["rememberHours"])
        model.set(.number(40), at: ["lighting", "brightness"])
        #expect(model.colorsAreDefault)
        model.setColor(.working, to: 0x112233)
        #expect(model.rgb(.working) == 0x112233)
        #expect(!model.colorsAreDefault)
        #expect(!model.config.urgentFirst)
        #expect(model.config.lighting.brightness == 0.4)
        model.save()
        #expect(onDisk(model) == """
        {
          "urgentFirst": false,
          "rememberHours": "always",
          "lighting": {
            "brightness": 40,
            "colors": {"working": "#112233"}
          }
        }

        """)
        model.resetColors()
        #expect(model.rgb(.working) == AgentStatus.working.color)
        #expect(model.colorsAreDefault)
    }

    @Test func aChangeTheBridgeWouldRefuseIsNotWritten() throws {
        let model = try model()
        model.set(.number(500), at: ["lighting", "brightness"])
        #expect(model.notice?.hasPrefix("Not saved.") == true)
        #expect(model.config == Config.builtIn)
        model.save()
        #expect(onDisk(model) == Config.defaultFileText)
        #expect(!FileManager.default.fileExists(atPath: model.files.config + ".before-app"))
        // The next change that is fine goes through and clears the notice.
        model.set(.number(50), at: ["lighting", "brightness"])
        #expect(model.notice == nil)
        #expect(model.config.lighting.brightness == 0.5)
    }

    @Test func aBrokenFileIsReportedAndLeftAlone() throws {
        let model = try model(config: "{ not json")
        #expect(!model.problems.isEmpty)
        #expect(model.nextStep != nil)
        model.setKeycap("ACT06", to: "REJ")
        #expect(model.notice?.contains("not valid JSON") == true)
        model.save()
        #expect(onDisk(model) == "{ not json")
    }

    @Test func aFileWithAMistakeKeepsItsOtherSettings() throws {
        // Valid JSON that the bridge refuses: the window says so and does not pile a change on top.
        let model = try model(config: #"{"keys": {"ACT99": "cmd:FAST"}, "urgentFirst": false}"#)
        #expect(!model.problems.isEmpty)
        model.set(.bool(true), at: ["layerWarning"])
        #expect(model.notice?.hasPrefix("Not saved.") == true)
        model.save()
        #expect(onDisk(model) == #"{"keys": {"ACT99": "cmd:FAST"}, "urgentFirst": false}"#)
    }

    @Test func withNoFileTheFirstChangeWritesOne() throws {
        let model = try model(config: nil)
        #expect(model.config == Config.builtIn)
        #expect(model.problems.isEmpty)
        model.setKeycap("ACT09", to: "NEW")
        model.save()
        let saved = try Config.parse(try #require(onDisk(model)))
        #expect(saved.bindings["ACT09.press"] == actions("cmd:NEW"))
        #expect(!FileManager.default.fileExists(atPath: model.files.config + ".before-app"))
    }

    @Test func aFileChangedByHandIsPickedUp() throws {
        let model = try model()
        try #"{"keys": {"ACT06": ["text:hello", "key:return"]}}"#.write(toFile: model.files.config, atomically: true,
                                                                       encoding: .utf8)
        // The file system's clock is coarse; make sure the change shows.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                              ofItemAtPath: model.files.config)
        model.refresh()
        #expect(model.keycap("ACT06").cap == .custom(#"["text:hello","key:return"]"#))
        #expect(model.legend("ACT06") == "Custom")
        #expect(model.face("ACT06") == .symbol("slider.horizontal.3"))
        // A command with no picture of its own shows the start of its name.
        #expect(model.face(ofCommand: "NOTES") == .text("NOT"))
        #expect(model.does("ACT06", "press").claude == actions("text:hello", "key:return"))
    }

    /// The drawing follows the pad as it is built: the dial top left, the stick top right, the
    /// layer button bottom left, and every row four places wide.
    @Test func theDrawingIsLaidOutLikeThePad() {
        let rows = PadDrawing.rows
        #expect(rows.count == 4)
        #expect(rows[0] == [.dial, .agent(0), .agent(1), .stick])
        #expect(rows[1] == [.agent(2), .agent(3), .agent(4), .agent(5)])
        #expect(rows[3].first == .layerButton)
        #expect(rows[3].last == .key("ACT12", wide: 1))
        for row in rows {
            let width = row.reduce(0) { sum, spot in
                if case let .key(_, wide) = spot { return sum + wide }
                return sum + 1
            }
            #expect(width == 4)
        }
        // Every key the file can bind is on the drawing once.
        let keys = rows.joined().compactMap { spot -> String? in
            if case let .key(name, _) = spot { return name }
            return nil
        }
        #expect(keys.sorted() == PadControl.keyTitles.keys.sorted())
    }

    @Test func theBridgesAnswerIsRead() throws {
        let reply = try #require(JSONValue.parse("""
        {"ok":true,"connected":true,"slots":["idle","needs-you","off","off","working","done"],
         "sessions":[{"slot":1,"session":"a","status":"needs-you","cwd":"/code/shop","host":"claude:local_1","pinned":true},
                     {"session":"b","status":"working","cwd":"/code/api","ended":true}],
         "pulsing":[1],"model":"Codex Micro","firmware":"v0.6.1","transport":"USB","battery":64,"charging":false,
         "layer":2,"inputMonitoring":"granted","accessibility":false}
        """))
        let bridge = BridgeSnapshot(reply: reply)
        #expect(bridge.running && bridge.connected)
        #expect(bridge.slots == [.idle, .needsYou, .off, .off, .working, .done])
        #expect(bridge.sessions.map(\.name) == ["shop", "api"])
        #expect(bridge.sessions[0].slot == 1 && bridge.sessions[1].slot == nil && bridge.sessions[1].ended)
        #expect(bridge.sessions[0].pinned && !bridge.sessions[1].pinned)
        #expect(bridge.pulsing == [1])
        #expect(bridge.firmware == "v0.6.1" && bridge.battery == 64 && bridge.charging == false && bridge.layer == 2)
        #expect(bridge.inputMonitoring == "granted" && bridge.accessibility == false)
        // No answer at all: the bridge is not running.
        #expect(!BridgeSnapshot().running)
    }

    @Test func theDemoKeepsItsSessionsByTheBridgesRules() throws {
        let model = BridgeModel(demo: true)
        #expect(model.bridge.running && model.bridge.connected)
        #expect(model.pinnedSlots == [3])
        #expect(model.waiting.map(\.name) == ["infra"])
        let docs = try #require(model.session(onSlot: 3))
        #expect(docs.pinned && docs.ended && docs.name == "docs-site")

        // No longer pinned, the ended session gives its key to the one that waits.
        model.unpin(docs)
        #expect(model.session(onSlot: 3)?.name == "infra" && model.waiting.isEmpty)
        #expect(model.pinnedSlots.isEmpty)

        // Pinned to a key another session holds, the two trade places.
        model.pin(try #require(model.session(onSlot: 0)), to: 5)
        #expect(model.session(onSlot: 5)?.name == "storefront" && model.session(onSlot: 5)?.pinned == true)
        #expect(model.session(onSlot: 0)?.name == "design-system")
        #expect(model.pinnedSlots == [5])

        model.forget(try #require(model.session(onSlot: 5)))
        #expect(model.session(onSlot: 5) == nil && model.pinnedSlots.isEmpty)
        #expect(model.bridge.slots[5] == .off)
    }

    @Test func doubleTapToPinIsOneSwitch() throws {
        let model = try model()
        #expect(model.trigger("doubleTap", of: "agentKeys") == nil)
        model.setTrigger("doubleTap", of: "agentKeys", to: .string("pin"))
        #expect(model.config.actions(for: "AG", "doubleTap") == [.pin])
        #expect(model.config.actions(for: "AG", "press") == actions("ack", "jump", "pane:chat"))
        #expect(model.config.actions(for: "AG", "hold") == actions("forget"))
        model.setTrigger("doubleTap", of: "agentKeys", to: nil)
        #expect(model.config == Config.builtIn)
    }

    /// What the Behavior tab's "Two taps pass the pad to ChatGPT" switch does, on and off.
    @Test func theTwoTapSwitchSetsLayerTwoForChatGPTAndClearsIt() throws {
        let model = try model()
        #expect(model.config.layers[2] == nil)

        model.set(.string(PadSharing.chatGPT), at: ["layers", "2"])
        #expect(model.config.layers[2] == PadSharing.chatGPT)
        model.save()
        #expect(try Config.load(model.files.config).layers == [2: PadSharing.chatGPT])
        #expect(model.problems.isEmpty)

        model.set(nil, at: ["layers", "2"])
        #expect(model.config.layers[2] == nil)
        model.save()
        #expect(try Config.load(model.files.config).layers.isEmpty)
        #expect(model.problems.isEmpty)
    }

    // MARK: Orca

    @Test func orcasKeysAreReadFromTheBridgesAnswer() throws {
        let reply = try #require(JSONValue.parse("""
        {"ok":true,"connected":true,"slots":["off","off","off","off","off","off"],"sessions":[],"layer":2,
         "orca":{"layer":2,"slots":["off","working","off","idle","off","off"],"keys":[
           {"slot":1,"session":"chat-one","status":"working","title":"Fix the build"},
           {"slot":3,"session":"chat-two","status":"idle","closed":true},
           {"slot":9,"session":"chat-three","status":"idle"}]}}
        """))
        let orca = try #require(BridgeSnapshot(reply: reply).orca)
        #expect(orca.layer == 2)
        #expect(orca.keys.map(\.slot) == [1, 3])
        #expect(orca.key(1) == OrcaKeyRow(slot: 1, chat: "chat-one", status: .working, title: "Fix the build"))
        #expect(orca.key(3)?.closed == true && orca.key(3)?.title == nil)
        #expect(orca.key(0) == nil)
        #expect(orca.slots == [.off, .working, .off, .idle, .off, .off])
        // A bridge with no layer for Orca says nothing of it.
        #expect(BridgeSnapshot(reply: try #require(JSONValue.parse(#"{"ok":true,"connected":true}"#))).orca == nil)
    }

    @Test func orcasChatsAreReadFromTheBridgesAnswer() throws {
        let reply = try #require(JSONValue.parse("""
        {"ok":true,"chats":[{"session":"chat-one","title":"Fix the build","status":"needs-you","worktree":"repo::/code/app"},
                            {"session":"chat-two","title":"New chat","status":"something-new","worktree":""},
                            {"title":"A chat with no ID"}]}
        """))
        #expect(BridgeModel.orcaChats(reply: reply) == [
            OrcaChat(id: "chat-one", title: "Fix the build", worktree: "repo::/code/app", status: .needsYou),
            OrcaChat(id: "chat-two", title: "New chat", worktree: "", status: .idle),
        ])
        #expect(BridgeModel.orcaChats(reply: try #require(JSONValue.parse(#"{"ok":false,"error":"Orca is not running"}"#))).isEmpty)
    }

    /// A key's row says the chat's title: Orca's when the chat is open, the one the bridge
    /// kept when it is closed, and the start of the ID when neither is known.
    @Test func aKeysRowNamesItsChat() {
        let model = BridgeModel(demo: true)
        model.showOrca(padThere: true)
        let orca = model.bridge.orca
        #expect(orca?.layer == 2 && model.bridge.layer == 2)
        #expect(orca?.slots == [.working, .needsYou, .done, .idle, .off, .off])
        #expect(orca?.key(3)?.closed == true)
        #expect((0 ..< 4).compactMap { orca?.key($0) }.map(model.orcaTitle) == [
            "Fix the checkout total", "Write the release notes", "Rename the billing tables", "Review the login flow",
        ])
        #expect(model.orcaTitle(OrcaKeyRow(slot: 5, chat: "0a1b2c3d-and-more", status: .idle)) == "Chat 0a1b2c3d")
        #expect(model.orcaChatsOffKeys.map(\.title) == ["Plan the search page"])
    }

    /// The window's buttons on Orca's keys do what a hold and a tap do, by the bridge's rules.
    @Test func theDemoTakesAndFreesOrcasKeys() throws {
        let model = BridgeModel(demo: true)
        model.showOrca()
        let plan = try #require(model.orcaChatsOffKeys.first)

        // A taken key takes nothing more.
        model.orcaTake(slot: 0, chat: plan.id)
        #expect(model.bridge.orca?.key(0)?.chat == "demo-chat-0")
        model.orcaTake(slot: 4, chat: plan.id)
        #expect(model.bridge.orca?.key(4)?.chat == plan.id)
        #expect(model.bridge.orca?.key(4).map(model.orcaTitle) == "Plan the search page")
        #expect(model.orcaChatsOffKeys.isEmpty)

        // Freed, an open chat can be taken again, and a closed one is gone.
        model.orcaFree(slot: 4)
        #expect(model.bridge.orca?.key(4) == nil && model.orcaChatsOffKeys.map(\.id) == [plan.id])
        model.orcaFree(slot: 3)
        #expect(model.bridge.orca?.keys.map(\.slot) == [0, 1, 2])
        // With no chat named, the key takes the chat on screen: here, the first one free.
        model.orcaTake(slot: 5)
        #expect(model.bridge.orca?.key(5)?.chat == plan.id)
    }

    /// What the Behavior tab's "Orca's chats have a layer of their own" switch writes. A layer
    /// is the bridge's own or another app's, so ChatGPT's layer moves out of the way and back.
    @Test func orcasLayerSwitchMovesChatGPTsLayerOutOfTheWay() throws {
        let model = try model(config: #"{"layers": {"2": "com.openai.codex"}}"#)
        #expect(model.orcaLayer == nil && model.chatGPTLayer == 2)

        model.setOrcaLayer(true)
        #expect(model.orcaLayer == 2 && model.chatGPTLayer == 3)
        #expect(model.notice == nil && model.problems.isEmpty)
        model.save()
        let saved = try Config.load(model.files.config)
        #expect(saved.layerApps[2] == ["orca"] && saved.layers == [3: PadSharing.chatGPT])

        model.setOrcaLayer(false)
        #expect(model.orcaLayer == nil && model.chatGPTLayer == 2)
        model.save()
        #expect(try Config.load(model.files.config).layerApps[2] == nil)
        #expect(try Config.load(model.files.config).layers == [2: PadSharing.chatGPT])
    }

    @Test func chatGPTsSwitchTakesTheFirstLayerThatIsFree() throws {
        let model = try model(config: "{}")
        model.setOrcaLayer(true)
        #expect(model.orcaLayer == 2 && model.chatGPTLayer == nil)
        model.setChatGPTLayer(true)
        #expect(model.chatGPTLayer == 3)
        model.setChatGPTLayer(false)
        #expect(model.chatGPTLayer == nil && model.config.layers.isEmpty)

        // With no layer for Orca it is layer 2, as before.
        model.setOrcaLayer(false)
        model.setChatGPTLayer(true)
        #expect(model.chatGPTLayer == 2 && model.problems.isEmpty)
    }

    /// Layer 2 given to other apps by hand is left as it is.
    @Test func orcasLayerSwitchLeavesALayerGivenByHand() throws {
        let model = try model(config: #"{"layerApps": {"2": ["com.apple.Notes"]}}"#)
        model.setOrcaLayer(true)
        #expect(model.orcaLayer == nil)
        #expect(model.notice == "Not done: layer 2 is given to other apps in the config file.")
        #expect(model.config.layerApps[2] == ["com.apple.Notes"])
    }

    @Test func theKeysOnLayerTwoSwitchSetsLayerKeysAndClearsIt() throws {
        let model = try model()
        #expect(!model.config.layerKeys)

        model.set(.bool(true), at: ["layerKeys"])
        #expect(model.config.layerKeys)
        model.save()
        #expect(try Config.load(model.files.config).layerKeys)
        #expect(model.problems.isEmpty)

        model.set(.bool(false), at: ["layerKeys"])
        model.save()
        #expect(try !Config.load(model.files.config).layerKeys)
        #expect(model.problems.isEmpty)
    }
}
