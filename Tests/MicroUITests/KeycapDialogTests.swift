import AppKit
import MicroKit
import Testing
@testable import MicroUI

/// The keycap dialog: what is picked in it reaches the file on Save and not before.
@MainActor @Suite struct KeycapDialogTests {
    private func dialog(_ model: BridgeModel, _ state: WindowState, _ key: String) -> KeycapDialog {
        KeycapDialog(model: model, state: state, key: key)
    }

    @Test func aPickedKeycapWaitsForSave() {
        let model = BridgeModel(demo: true)
        let state = WindowState(tab: .keys)
        #expect(model.keycap("ACT09").cap == .command("SPLIT"))

        state.editKeycap("ACT09", current: model.keycap("ACT09").cap)
        #expect(state.keycapKey == "ACT09")
        #expect(dialog(model, state, "ACT09").unchanged)
        dialog(model, state, "ACT09").pick("NEW")
        #expect(!dialog(model, state, "ACT09").unchanged)
        #expect(model.keycap("ACT09").cap == .command("SPLIT"))
        dialog(model, state, "ACT09").cancel()
        #expect(state.keycapKey == nil)
        #expect(model.keycap("ACT09").cap == .command("SPLIT"))
        #expect(model.keycap("ACT09").isDefault)

        state.editKeycap("ACT09", current: model.keycap("ACT09").cap)
        #expect(state.keycapDraft == .command("SPLIT"))
        dialog(model, state, "ACT09").pick("NEW")
        dialog(model, state, "ACT09").save()
        #expect(state.keycapKey == nil)
        #expect(model.keycap("ACT09").cap == .command("NEW"))
        #expect(model.face("ACT09") == .symbol("square.and.pencil"))
        // The other keys are as they were.
        #expect(model.keycap("ACT07").cap == .command("APPR"))
    }

    @Test func savingWhatTheKeyHasWritesNothing() {
        let model = BridgeModel(demo: true)
        let state = WindowState(tab: .keys)
        state.editKeycap("ACT07", current: model.keycap("ACT07").cap)
        dialog(model, state, "ACT07").save()
        #expect(state.keycapKey == nil)
        #expect(model.keycap("ACT07").isDefault)
        #expect(model.notice == nil)
    }

    @Test func aKeyCanRunItsOwnActionsOrNothing() throws {
        let model = BridgeModel(demo: true)
        let state = WindowState(tab: .keys)
        let press = ActionList(owner: .key("ACT08"), trigger: "press")

        state.editKeycap("ACT08", current: model.keycap("ACT08").cap)
        dialog(model, state, "ACT08").setMode(.own)
        #expect(dialog(model, state, "ACT08").mode == .own)
        #expect(model.keycap("ACT08").cap == .command("REJ"))
        dialog(model, state, "ACT08").save()
        // Its press starts as the command the key ran.
        #expect(model.actions(in: press) == ["cmd:REJ"])
        if case .custom = model.keycap("ACT08").cap {} else { Issue.record("the key should have its own actions") }

        state.editKeycap("ACT08", current: model.keycap("ACT08").cap)
        #expect(dialog(model, state, "ACT08").unchanged)
        dialog(model, state, "ACT08").setMode(.nothing)
        dialog(model, state, "ACT08").save()
        #expect(model.keycap("ACT08").cap == .nothing)
        #expect(model.face("ACT08") == .blank)

        // Back to a command from nothing: the first one on offer is picked, and waits for Save.
        state.editKeycap("ACT08", current: model.keycap("ACT08").cap)
        dialog(model, state, "ACT08").setMode(.command)
        let first = try #require(dialog(model, state, "ACT08").names.first)
        #expect(state.keycapDraft == Keycap.command(first))
        #expect(model.keycap("ACT08").cap == .nothing)
    }

    @Test func searchFindsACommandByNameOrTitle() {
        let model = BridgeModel(demo: true)
        let state = WindowState(tab: .keys)
        state.editKeycap("ACT07", current: model.keycap("ACT07").cap)
        let all = dialog(model, state, "ACT07").names
        // The commands on the pad come first, and a command that does nothing is not on offer.
        #expect(all.first == "APPR")
        #expect(all.contains("NEW"))
        #expect(!all.contains("PLAY"))
        state.keycapSearch = "appr"
        #expect(dialog(model, state, "ACT07").names == ["APPR"])
        state.keycapSearch = "Decline"
        #expect(dialog(model, state, "ACT07").names == ["REJ"])
        state.keycapSearch = "no such command"
        #expect(dialog(model, state, "ACT07").names.isEmpty)
        // Opening the dialog again starts with every command.
        state.editKeycap("ACT07", current: model.keycap("ACT07").cap)
        #expect(dialog(model, state, "ACT07").names == all)
    }

    @Test func eachKeySaysWhatItRuns() {
        let model = BridgeModel(demo: true)
        #expect(model.keyNames["ACT07"] == "Approve")
        #expect(model.keyNames["ACT08"] == "Decline")
        model.setKeycap("ACT08", to: nil)
        #expect(model.keyNames["ACT08"] == "nothing")
        model.giveKeyOwnActions("ACT07")
        #expect(model.keyNames["ACT07"] == "its own actions")
        #expect(Set(model.keyNames.keys) == Set(PadControl.keyTitles.keys))
    }

    @Test func theDialTurnsThroughAnswersOrSessions() {
        let model = BridgeModel(demo: true)
        #expect(model.dialTurn == .answers)
        model.setDialTurn(.sessions)
        #expect(model.dialTurn == .sessions)
        #expect(model.trigger("cw", of: "dial") == .string("cmd:BACK"))
        #expect(model.trigger("ccw", of: "dial") == .string("cmd:FORWARD"))
        // The press and the hold are as they were.
        #expect(model.trigger("press", of: "dial") == .string("cmd:PICK"))
        #expect(model.trigger("hold", of: "dial") == .string("cmd:PADSETTINGS"))
        // Swapped directions are still the same choice.
        model.swapDial()
        #expect(model.dialTurn == .sessions)
        model.setDialTurn(.answers)
        #expect(model.dialTurn == .answers)
        #expect(model.sectionIsDefault("dial"))
        // Anything else is the person's own, and choosing it writes nothing.
        model.setTrigger("cw", of: "dial", to: .string("key:cmd+]"))
        #expect(model.dialTurn == .own)
        model.setDialTurn(.own)
        #expect(model.trigger("cw", of: "dial") == .string("key:cmd+]"))
    }

    @Test func theLockSwitchIsWrittenToTheFile() {
        let model = BridgeModel(demo: true)
        #expect(!model.config.lighting.offWhenLocked)
        model.set(.bool(true), at: ["lighting", "offWhenLocked"])
        #expect(model.config.lighting.offWhenLocked)
        #expect(model.notice == nil)
    }

    @Test func everyCommandPictureIsARealSymbol() {
        for (command, symbol) in BridgeModel.symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(command): \(symbol)")
        }
    }
}
