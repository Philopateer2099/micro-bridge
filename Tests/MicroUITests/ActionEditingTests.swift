import Foundation
import MicroKit
import Testing
@testable import MicroUI

/// The window's action lists and commands, on files in a folder made for each test.
@MainActor @Suite struct ActionEditingTests {
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

    private func onDisk(_ model: BridgeModel) throws -> String {
        model.save()
        return String(decoding: try #require(FileManager.default.contents(atPath: model.files.config)), as: UTF8.self)
    }

    private func actions(_ texts: String...) -> [Action] {
        texts.compactMap(Action.parse)
    }

    private func list(_ owner: ActionList.Owner, _ trigger: String = "press") -> ActionList {
        ActionList(owner: owner, trigger: trigger)
    }

    // MARK: Drafts

    @Test func everyKindReadsAndWritesItsSpelling() {
        let spellings = [
            "cmd:APPR", "key:cmd+shift+m", "keydown:space", "keyup:space", "text:/fast\n", "text:Use computer use to ",
            "click:epitaxy-approval-card/=Next!", "choose:epitaxy-approval-card/epitaxy-answer-option+Next|Submit/next",
            "sh:open -t \"$HOME/notes.txt\"", "open:https://code.claude.com/docs", "ack", "jump", "focus", "forget", "pin", "lock",
            "scroll:up", "scroll:down", "pane:left", "pane:right", "pane:chat",
        ]
        for spelling in spellings {
            let draft = ActionDraft(spelling: spelling)
            #expect(draft?.spelling == spelling, "\(spelling)")
            #expect(draft?.problem(inCommand: false) == nil, "\(spelling)")
        }
        #expect(Set(spellings.compactMap { ActionDraft(spelling: $0)?.kind }) == Set(ActionKind.allCases))
    }

    @Test func textKeepsItsSpacesAndItsReturn() {
        let sent = ActionDraft(spelling: "text:/fast\n")
        #expect(sent == ActionDraft(kind: .text, value: "/fast", sends: true))
        let open = ActionDraft(spelling: "text:Use computer use to ")
        #expect(open == ActionDraft(kind: .text, value: "Use computer use to ", sends: false))
        #expect(ActionDraft(kind: .text, value: " two words ", sends: true).spelling == "text: two words \n")
        // Return on its own is still something to type.
        #expect(ActionDraft(kind: .text, sends: true).problem(inCommand: false) == nil)
        #expect(ActionDraft(kind: .text).problem(inCommand: false) == ActionKind.text.advice)
    }

    @Test func aDraftSaysWhyItCannotBeSaved() {
        #expect(ActionDraft(kind: .key, value: "cmd+").problem(inCommand: false) == ActionKind.key.advice)
        #expect(ActionDraft(kind: .key, value: " CMD+B ").spelling == "key:CMD+B")
        #expect(ActionDraft(kind: .key, value: " CMD+B ").problem(inCommand: false) == nil)
        #expect(ActionDraft(kind: .click, value: "no slash").problem(inCommand: false) == ActionKind.click.advice)
        #expect(ActionDraft(kind: .shell).problem(inCommand: false) == ActionKind.shell.advice)
        #expect(ActionDraft(kind: .command).problem(inCommand: false) == ActionKind.command.advice)
        #expect(ActionDraft(kind: .command, value: "appr").spelling == "cmd:APPR")
        #expect(ActionDraft(kind: .command, value: "APPR").problem(inCommand: true) == "A command cannot run another command.")
        #expect(ActionDraft(kind: .pin).spelling == "pin")
        // The window does not edit these as actions.
        #expect(ActionDraft(spelling: "none") == nil)
        #expect(ActionDraft(spelling: "key:nokey") == nil)
        #expect(ActionDraft(spelling: "launch:rockets") == nil)
        #expect(!ActionKind.groups(inCommand: true).joined().contains(.command))
        #expect(Set(ActionKind.groups(inCommand: false).joined()) == Set(ActionKind.allCases))
    }

    // MARK: Keys

    @Test func aCommandKeyGetsItsOwnActions() throws {
        let model = try model()
        #expect(model.lists(of: .key("ACT09")).map(\.trigger) == ["press"])
        model.giveKeyOwnActions("ACT09")
        #expect(model.keycap("ACT09").cap == .custom(#"{"press":"cmd:SPLIT"}"#))
        #expect(model.actions(in: list(.key("ACT09"))) == ["cmd:SPLIT"])
        // The press still forks, in each app its own way.
        #expect(model.does("ACT09", "press").terminal == actions("text:/branch\n"))

        let added = model.setActions(["cmd:SPLIT", "key:cmd+b"], in: list(.key("ACT09")))
        #expect(added)
        let held = model.setActions(["text:/compact\n"], in: list(.key("ACT09"), "hold"))
        #expect(held)
        #expect(model.notice == nil)
        #expect(try onDisk(model).contains(#"    "ACT09": {"press": ["cmd:SPLIT", "key:cmd+b"], "hold": "text:/compact\n"},"#))
        #expect(model.does("ACT09", "press").claude == actions("key:cmd+opt+o", "key:cmd+b"))
        #expect(model.does("ACT09", "hold").claude == actions("text:/compact\n"))
        #expect(model.does("ACT09", "release").claude.isEmpty)
        // No other key changed.
        #expect(model.config.bindings.filter { !$0.key.hasPrefix("ACT09.") }
            == Config.builtIn.bindings.filter { !$0.key.hasPrefix("ACT09.") })
    }

    @Test func aKeyWithNoActionsLeftStaysItsOwn() throws {
        let model = try model()
        model.giveKeyOwnActions("ACT12")
        let emptied = model.setActions([], in: list(.key("ACT12")))
        #expect(emptied)
        #expect(model.keycap("ACT12").cap == .custom("{}"))
        #expect(model.lists(of: .key("ACT12")).isEmpty)
        #expect(try onDisk(model).contains(#"    "ACT12": {}"#))
        #expect(model.does("ACT12", "press").claude.isEmpty)
        // A key that did nothing starts with no lists.
        model.setKeycap("ACT06", to: nil)
        model.giveKeyOwnActions("ACT06")
        #expect(model.keycap("ACT06").cap == .custom("{}"))
        model.resetKey("ACT12")
        #expect(model.keycap("ACT12") == (.command("CODEX"), true))
    }

    @Test func aKeyWrittenByHandIsReadInEveryForm() throws {
        let model = try model(config: """
        {"keys": {"ACT06": ["cmd:FAST"], "ACT07": ["key:a", "none", "key:b"], "ACT08": "key:escape", "ACT09": [],
                  "ACT12": {"press": "key:return", "doubleTap": ["key:up", "key:return"]}}}
        """)
        #expect(model.problems.isEmpty)
        #expect(model.keycap("ACT06").cap == .command("FAST"))
        #expect(model.actions(in: list(.key("ACT07"))) == ["key:a", "key:b"])
        #expect(model.keycap("ACT08").cap == .custom("key:escape"))
        #expect(model.actions(in: list(.key("ACT08"))) == ["key:escape"])
        #expect(model.keycap("ACT09").cap == .nothing)
        #expect(model.lists(of: .key("ACT12")).map(\.trigger) == ["press", "doubleTap"])
        #expect(model.actions(in: list(.key("ACT12"), "doubleTap")) == ["key:up", "key:return"])

        // Moving an action up rewrites that list and keeps the other trigger.
        let moved = model.setActions(["key:return", "key:up"], in: list(.key("ACT12"), "doubleTap"))
        #expect(moved)
        #expect(try onDisk(model).contains(#""ACT12": {"press": "key:return", "doubleTap": ["key:return", "key:up"]}"#))
    }

    // MARK: Agent Keys, dial, stick

    @Test func aSectionKeepsItsOtherTriggers() throws {
        let model = try model()
        let pinned = model.setActions(["pin"], in: list(.section("agentKeys"), "doubleTap"))
        #expect(pinned)
        #expect(try onDisk(model).contains(#"""
          "agentKeys": {
            "press": ["ack", "jump", "pane:chat"],
            "hold": "forget",
            "doubleTap": "pin"
          },
        """#))
        #expect(model.trigger("doubleTap", of: "agentKeys") == .string("pin"))

        let turned = model.setActions(["cmd:NEXT", "key:tab"], in: list(.section("dial"), "ccw"))
        #expect(turned)
        #expect(model.does("DIAL", "ccw").terminal == actions("key:down", "key:tab"))
        #expect(model.does("DIAL", "cw").terminal == actions("key:up"))
        #expect(model.does("DIAL", "hold").terminal == Config.builtIn.actions(for: "DIAL", "hold"))

        let cleared = model.setActions([], in: list(.section("stick"), "down"))
        #expect(cleared)
        #expect(model.lists(of: .section("stick")).map(\.trigger) == ["up", "right", "left"])
        #expect(model.does("STICK", "down").claude.isEmpty)
        #expect(model.does("STICK", "up").claude == actions("key:cmd+shift+m"))
    }

    // MARK: Commands

    @Test func changingOneAppOfACommandKeepsTheOthers() throws {
        let model = try model(config: "{}")
        #expect(model.commandIsDefault("APPR") && model.commandIsBuiltIn("APPR"))
        #expect(model.commandTargets("APPR") == ["claude", "terminal", "default"])
        #expect(model.actions(in: list(.command("APPR", target: "default"))) == ["key:return"])
        #expect(model.actions(in: list(.command("APPR", target: "terminal"))).isEmpty)

        let set = model.setActions(["key:1"], in: list(.command("APPR", target: "terminal")))
        #expect(set)
        #expect(!model.commandIsDefault("APPR"))
        #expect(model.does("ACT07", "press").terminal == actions("key:1"))
        #expect(model.does("ACT07", "press").claude == Config.builtIn.actions(for: "ACT07", "press", app: model.claudeApp))
        #expect(model.config.command("APPR", app: "com.apple.Safari")?["press"] == actions("key:return"))
        // Only this command is in the file; the others are still the bridge's own.
        let saved = try onDisk(model)
        #expect(saved.contains(#""default": "key:return""#) && saved.contains(#""terminal": "key:1""#))
        #expect(!saved.contains("REJ"))
        #expect(model.config.commands.filter { $0.key != "APPR" } == Config.builtIn.commands.filter { $0.key != "APPR" })

        // An app with nothing of its own does what every other app does.
        let unset = model.setActions([], in: list(.command("APPR", target: "terminal")))
        #expect(unset)
        #expect(model.commandIsDefault("APPR"))
        #expect(model.does("ACT07", "press").terminal == actions("key:return"))

        model.removeCommand("APPR")
        #expect(model.file?.value(at: ["commands", "APPR"]) == nil)
        #expect(model.config == Config.builtIn)
    }

    @Test func aCommandCanHaveSeveralTriggersInOneApp() throws {
        let model = try model(config: "{}")
        let pressed = model.setActions(["keydown:f5"], in: list(.command("FAST", target: "claude")))
        let released = model.setActions(["keyup:f5"], in: list(.command("FAST", target: "claude"), "release"))
        #expect(pressed && released)
        #expect(try onDisk(model).contains(
            #""FAST": {"default": "text:/fast\n", "claude": {"press": "keydown:f5", "release": "keyup:f5"}}"#))
        #expect(model.does("ACT06", "release").claude == actions("keyup:f5"))
        #expect(model.does("ACT06", "release").terminal.isEmpty)
        #expect(model.lists(of: .command("MIC", target: "terminal")).map(\.trigger) == ["press", "release"])

        // Back to a press alone, it is written the short way.
        let dropped = model.setActions([], in: list(.command("FAST", target: "claude"), "release"))
        #expect(dropped)
        #expect(try onDisk(model).contains(#""FAST": {"default": "text:/fast\n", "claude": "keydown:f5"}"#))
    }

    @Test func aCommandCannotRunACommand() throws {
        let model = try model(config: "{}")
        let refused = model.setActions(["cmd:REJ"], in: list(.command("APPR", target: "terminal")))
        #expect(!refused)
        #expect(model.notice?.contains("a command cannot use cmd:") == true)
        #expect(model.config == Config.builtIn)
        #expect(model.commandIsDefault("APPR"))
    }

    @Test func aCommandIsMadeUsedAndRemoved() throws {
        let model = try model(config: "{}")
        #expect(model.addCommand("no spaces") == "A name is 1 to 24 letters, digits, + - or _.")
        #expect(model.addCommand("") == "A name is 1 to 24 letters, digits, + - or _.")
        #expect(model.addCommand("appr") == "There is already a command called APPR.")
        #expect(model.addCommand(" notes ") == nil)
        // It is listed after the commands on the pad and before the bridge's own unused ones.
        let listed = model.allCommands
        #expect(try #require(listed.firstIndex(of: "NOTES")) > #require(listed.firstIndex(of: "CODEX")))
        #expect(try #require(listed.firstIndex(of: "NOTES")) < #require(listed.firstIndex(of: "APPS")))
        #expect(!model.commandIsBuiltIn("NOTES") && !model.commandIsDefault("NOTES"))
        #expect(!model.commandDoesSomething("NOTES"))
        // A command that does nothing yet is not offered for a keycap.
        #expect(!model.commandNames.contains("NOTES"))

        let filled = model.setActions(["open:/System/Applications/Notes.app"], in: list(.command("NOTES", target: "default")))
        #expect(filled)
        #expect(model.commandNames.contains("NOTES"))
        #expect(model.uses(of: "NOTES").isEmpty)
        model.setKeycap("ACT09", to: "NOTES")
        #expect(model.uses(of: "NOTES") == ["Key 10"])
        #expect(model.allCommands.first == "APPR")
        #expect(model.does("ACT09", "press").claude == actions("open:/System/Applications/Notes.app"))
        #expect(try onDisk(model).contains(#""NOTES": {"default": "open:/System/Applications/Notes.app"}"#))

        // The bridge refuses a file whose key names a command that is gone, so nothing is removed.
        model.removeCommand("NOTES")
        #expect(model.notice?.contains("there is no command named NOTES") == true)
        #expect(model.config.commands["NOTES"] != nil)
        model.notice = nil
        model.resetKey("ACT09")
        model.removeCommand("NOTES")
        #expect(model.notice == nil)
        #expect(model.config == Config.builtIn)
        #expect(model.uses(of: "APPR") == ["Key 8"])
        #expect(model.uses(of: "PLAN") == ["Stick"])
        #expect(model.uses(of: "PICK") == ["Dial"])
    }

    @Test func aCommandWrittenByHandIsReadInEveryForm() throws {
        let model = try model(config: """
        {"apps": {"browser": ["com.apple.Safari"]},
         "commands": {"one": "key:a", "TWO": ["key:a", "key:b"], "THREE": {"press": "key:a", "hold": "key:b"},
                      "FOUR": {"com.apple.Notes": "key:n", "browser": {"release": "key:r"}}}}
        """)
        #expect(model.problems.isEmpty)
        #expect(model.actions(in: list(.command("ONE", target: "default"))) == ["key:a"])
        #expect(model.actions(in: list(.command("TWO", target: "default"))) == ["key:a", "key:b"])
        #expect(model.actions(in: list(.command("THREE", target: "default"), "hold")) == ["key:b"])
        #expect(model.commandTargets("FOUR") == ["claude", "terminal", "browser", "com.apple.Notes", "default"])
        #expect(model.targetTitle("browser") == "In the browser apps")
        #expect(model.targetTitle("com.apple.Notes") == "In com.apple.Notes")
        #expect(model.actions(in: list(.command("FOUR", target: "browser"), "release")) == ["key:r"])

        // A change keeps the name as the file has it, and turns a short form into targets.
        let grown = model.setActions(["key:c"], in: list(.command("ONE", target: "claude")))
        #expect(grown)
        #expect(try onDisk(model).contains(#""one": {"default": "key:a", "claude": "key:c"}"#))
        #expect(model.config.command("ONE", app: model.claudeApp)?["press"] == actions("key:c"))
        let held = model.setActions(["key:b", "key:c"], in: list(.command("THREE", target: "default"), "hold"))
        #expect(held)
        #expect(try onDisk(model).contains(#""THREE": {"default": {"press": "key:a", "hold": ["key:b", "key:c"]}}"#))
    }

    @Test func anAppThatIsToldToDoNothingStaysThatWay() throws {
        // Only the file can say "nothing in this one app". The window leaves it as it is.
        let model = try model(config: #"{"commands": {"NEW": {"claude": {}, "default": "key:cmd+n"}}}"#)
        #expect(model.problems.isEmpty)
        #expect(model.config.command("NEW", app: model.claudeApp)?["press"] == nil)
        #expect(model.actions(in: list(.command("NEW", target: "claude"))).isEmpty)
        let set = model.setActions(["text:/clear\n"], in: list(.command("NEW", target: "terminal")))
        #expect(set)
        #expect(try onDisk(model).contains(#""NEW": {"claude": {}, "default": "key:cmd+n", "terminal": "text:/clear\n"}"#))
        #expect(model.config.command("NEW", app: model.claudeApp)?["press"] == nil)
        #expect(model.config.command("NEW", app: "com.apple.Safari")?["press"] == actions("key:cmd+n"))
    }

    @Test func aCommandForAnAppGroupThatIsGoneIsRefused() throws {
        let model = try model(config: #"{"apps": {"claude": ["com.anthropic.claudefordesktop"]}}"#)
        // "apps" in the file adds to the bridge's groups, so terminal is still one.
        #expect(model.commandTargets("NEW").contains("terminal"))
        let refused = model.setActions(["key:a"], in: list(.command("NEW", target: "editors")))
        #expect(!refused)
        #expect(model.notice?.contains("no app group with that name") == true)
    }
}
