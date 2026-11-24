import Foundation
@testable import MicroKit
import Testing

/// What a command does in one app, changed in the file: the rule the MicroBridge window and
/// the bridge (for the panel in Orca) share, and the socket operations the panel uses.
@MainActor
struct CommandEditTests {
    static let allow = "click:native-chat-appearance/=Allow"

    private func actions(_ texts: String...) -> [Action] {
        texts.compactMap(Action.parse)
    }

    /// A command the file leaves out is written whole, because a command the file mentions
    /// does only what the file says.
    @Test func aChangeInOneAppKeepsTheCommandsOtherApps() throws {
        var file = try #require(ConfigFile(text: "{}"))
        #expect(file.commandLists("APPR", target: "orca", defaults: ConfigFile.builtIn).map(\.actions) == [[Self.allow]])
        file.setCommand("APPR", target: "orca", actions: ["key:cmd+return"], defaults: ConfigFile.builtIn)

        let config = try Config.parse(file.text)
        #expect(config.command("APPR", app: Orca.bundleID)?["press"] == actions("key:cmd+return"))
        #expect(config.command("APPR", app: "com.anthropic.claudefordesktop") == Config.builtIn.command("APPR", app: "com.anthropic.claudefordesktop"))
        #expect(config.command("APPR", app: "com.apple.Notes")?["press"] == actions("key:return"))
        #expect(config.commands["REJ"] == Config.builtIn.commands["REJ"])
    }

    @Test func aCommandOfTheFilesOwnKeepsItsNameAndItsParts() throws {
        var file = try #require(ConfigFile(text: #"{"commands": {"appr": {"default": "key:return"}}}"#))
        file.setCommand("APPR", target: "orca", actions: [Self.allow, "key:return"], defaults: ConfigFile.builtIn)
        #expect(file.text.contains(#""appr": {"default": "key:return", "orca": ["\#(Self.allow)", "key:return"]}"#))

        // A second trigger turns the entry into one list per trigger.
        file.setCommand("APPR", target: "orca", trigger: "hold", actions: ["key:escape"], defaults: ConfigFile.builtIn)
        #expect(file.commandLists("APPR", target: "orca", defaults: nil).map(\.trigger) == ["press", "hold"])
        #expect(try Config.parse(file.text).command("APPR", app: Orca.bundleID)?["hold"] == actions("key:escape"))

        // No actions takes the part away, and the last part takes the app's entry with it.
        file.setCommand("APPR", target: "orca", trigger: "hold", actions: [], defaults: ConfigFile.builtIn)
        file.setCommand("APPR", target: "orca", actions: [], defaults: ConfigFile.builtIn)
        #expect(file.text.contains(#""appr": {"default": "key:return"}"#))
        #expect(try Config.parse(file.text).command("APPR", app: Orca.bundleID)?["press"] == actions("key:return"))
    }

    @Test func theSocketAsksForCommandsAndChangesOne() throws {
        #expect(try Command.parse(#"{"op":"commands","target":"orca"}"#) == .commands(target: "orca"))
        #expect(try Command.parse(#"{"op":"command.set","name":"appr","target":"orca","actions":["key:return"]}"#)
            == .commandSet(name: "APPR", target: "orca", actions: ["key:return"]))
        #expect(try Command.parse(#"{"op":"command.set","name":"MIC","target":"default","trigger":"release","actions":[]}"#)
            == .commandSet(name: "MIC", target: "default", trigger: "release", actions: []))
        for bad in [#"{"op":"commands"}"#, #"{"op":"commands","target":"two words"}"#,
                    #"{"op":"command.set","name":"APPR","target":"orca"}"#,
                    #"{"op":"command.set","name":"a name","target":"orca","actions":[]}"#,
                    #"{"op":"command.set","name":"APPR","target":"orca","trigger":"shake","actions":[]}"#,
                    #"{"op":"command.set","name":"APPR","target":"orca","actions":[7]}"#] {
            #expect(throws: Command.Invalid.self, "\(bad)") { try Command.parse(bad) }
        }
        let row = Reply.CommandRow(name: "APPR", controls: ["Key 8"], here: [("press", [Self.allow])], elsewhere: [("press", ["key:return"])])
        #expect(Reply.commands([row]) == #"{"ok":true,"commands":[{"name":"APPR","title":"Approve","controls":["Key 8"],"#
            + #""here":{"press":["\#(Self.allow)"]},"elsewhere":{"press":["key:return"]}}]}"#)
    }

    @Test func theBridgeListsWhatTheCommandsDoInOrca() throws {
        let bench = try OwnLayerTests.bench()
        let rows = bench.daemon.commands(in: "orca")
        let approve = try #require(rows.first { $0.name == "APPR" })
        #expect(approve.here.elementsEqual([("press", [Self.allow])], by: ==))
        #expect(approve.elsewhere.elementsEqual([("press", ["key:return"])], by: ==))
        #expect(!approve.controls.isEmpty)
        // A command no control runs and that does nothing of its own in Orca is left out, and
        // the commands on the pad come first, in the pad's order.
        #expect(rows.allSatisfy { !$0.controls.isEmpty || !$0.here.isEmpty })
        #expect(approve.title == "Approve" && approve.controls == ["Key 8"])
        let onPad = rows.prefix { !$0.controls.isEmpty }
        #expect(!onPad.isEmpty && rows.dropFirst(onPad.count).allSatisfy(\.controls.isEmpty))
    }

    @Test func theBridgeWritesAChangeAndTurnsABadOneDown() throws {
        let bench = try OwnLayerTests.bench()
        let path = bench.directory + "/config.json"
        let before = try String(contentsOfFile: path, encoding: .utf8)

        #expect(bench.daemon.setCommand("APPR", target: "orca", actions: ["jump:the moon"]) == "jump:the moon: not an action the bridge knows")
        #expect(bench.daemon.setCommand("APPR", target: "orca", actions: ["cmd:REJ"]) == "cmd:REJ: a command cannot run another command")
        #expect(bench.daemon.setCommand("NOSUCH", target: "orca", actions: ["key:return"]) == "no command named NOSUCH")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == before)

        #expect(bench.daemon.setCommand("APPR", target: "orca", actions: [Self.allow, "key:return"]) == nil)
        let saved = try Config.load(path)
        #expect(saved.command("APPR", app: Orca.bundleID)?["press"] == actions(Self.allow, "key:return"))
        // The rest of the file is as it was, and the file from before is kept once.
        #expect(saved.layerApps[2] == ["orca"] && saved.bindings["ACT06.press"] == actions("ack"))
        #expect(try String(contentsOfFile: path + ".before-app", encoding: .utf8) == before)
        #expect(bench.said("command APPR: press in orca changed over the socket"))
        // The bridge acts on it at once.
        let approve = try #require(bench.daemon.commands(in: "orca").first { $0.name == "APPR" })
        #expect(approve.here.elementsEqual([("press", [Self.allow, "key:return"])], by: ==))
        // The same change again writes nothing.
        let stamp = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        #expect(bench.daemon.setCommand("APPR", target: "orca", actions: [Self.allow, "key:return"]) == nil)
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date == stamp)
    }

    @Test func aFileThatIsNotJSONIsLeftAlone() throws {
        let bench = try OwnLayerTests.bench()
        let path = bench.directory + "/config.json"
        try "{ not json".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(bench.daemon.setCommand("APPR", target: "orca", actions: ["key:return"])
            == "the config file is not valid JSON: fix it in an editor first")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "{ not json")
    }
}
