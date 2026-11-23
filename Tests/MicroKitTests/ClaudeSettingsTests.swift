import Foundation
import Testing
@testable import MicroKit

/// `micro hooks`: the bridge's hook in Claude Code's settings file. Every test works on a file in
/// its own temporary folder, never on the real ~/.claude/settings.json.
@Suite struct ClaudeSettingsTests {
    let folder = NSTemporaryDirectory() + "mb-settings-" + UUID().uuidString
    var path: String { folder + "/.claude/settings.json" }
    let command = "/Applications/MicroBridge.app/Contents/MacOS/micro hook"

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(atPath: folder + "/.claude", withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    func text() -> String? { FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } }

    func settings() -> JSONValue { text().flatMap(JSONValue.parseKeepingOrder) ?? .null }

    func backups() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder + "/.claude")) ?? []).filter { $0.contains(".bak-micro-") }
    }

    @Test func aNewAccountWithNoSettingsFileGetsOne() throws {
        #expect(try ClaudeSettings.status(path: path).first?.hasPrefix("0 of 11 events") == true)
        #expect(try ClaudeSettings.change(path: path, adding: nil, dryRun: false) == ["nothing to change"])
        #expect(try ClaudeSettings.change(path: path, adding: command, dryRun: true).first?.hasPrefix("would add") == true)
        #expect(text() == nil, "remove and a dry run leave the file missing")

        let said = try ClaudeSettings.change(path: path, adding: command, dryRun: false)
        #expect(said.first?.hasPrefix("created ") == true)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600, "only the user can read a new settings file")
        #expect(ClaudeSettings.registered(settings()).count == 11)
        #expect(try ClaudeSettings.change(path: path, adding: command, dryRun: false) == ["nothing to change"])
        #expect(backups().isEmpty, "there was nothing to back up")
    }

    @Test func otherSettingsAndOtherToolsHooksStayAsTheyWere() throws {
        let original = """
        {
          "model": "opus",
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "other-tool notify"
                  }
                ]
              }
            ]
          },
          "env": {}
        }

        """
        try write(original)
        let said = try ClaudeSettings.change(path: path, adding: command, dryRun: false)
        #expect(said.first == "added the hook to 11 events in \(path)")
        #expect(said.last?.hasPrefix("backup: ") == true)
        let added = try #require(text())
        #expect(added.contains("\"other-tool notify\"") && added.contains("\"model\": \"opus\""))
        #expect(added.hasPrefix("{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"Stop\": [\n"), "keys keep their order")

        _ = try ClaudeSettings.change(path: path, adding: nil, dryRun: false)
        #expect(text() == original, "remove gives back the file byte for byte")
        // Four changes in the same second keep four backups.
        _ = try ClaudeSettings.change(path: path, adding: command, dryRun: false)
        _ = try ClaudeSettings.change(path: path, adding: nil, dryRun: false)
        #expect(backups().count == 4)
    }

    @Test func aBrokenFileIsLeftAlone() throws {
        try write("{\"model\": ")
        #expect(throws: ClaudeSettings.Problem.notJSON(path)) {
            try ClaudeSettings.change(path: path, adding: command, dryRun: false)
        }
        #expect(text() == "{\"model\": ")
        #expect(backups().isEmpty)
    }

    @Test func aMovedAppIsPointedAtItsNewPlace() throws {
        let old = "/Users/x/Applications/MicroBridge.app/Contents/MacOS/micro hook"
        try write(ClaudeSettings.installing(old, into: .object([])).indented + "\n")
        let said = try ClaudeSettings.change(path: path, adding: command, dryRun: false)
        #expect(said.first == "pointed the hook at \(command) in \(path)")
        let now = try #require(text())
        #expect(!now.contains(old) && now.components(separatedBy: command).count - 1 == 11, "one entry per event, none doubled")
    }

    @Test func removeTakesTheHookOutWhereverTheAppIs() {
        let quoted = ClaudeSettings.command(executable: "/Users/x/My Apps/MicroBridge.app/Contents/MacOS/micro")
        #expect(quoted == "'/Users/x/My Apps/MicroBridge.app/Contents/MacOS/micro' hook")
        let both = ClaudeSettings.installing(quoted, into: .object([]))
        #expect(ClaudeSettings.registered(both).count == 11)
        #expect(ClaudeSettings.registered(ClaudeSettings.removing(from: both)).isEmpty)
        #expect(ClaudeSettings.removing(from: both)["hooks"] == .object([]), "events left empty go")
    }

    @Test func thePluginAndTheSettingsHookAreNeverBothOn() throws {
        try write("{\n  \"enabledPlugins\": {\n    \"micro-bridge@micro-bridge\": true\n  }\n}\n")
        #expect(try ClaudeSettings.status(path: path).last == "the MicroBridge plugin is on in Claude Code")
        #expect(throws: ClaudeSettings.Problem.pluginOn) {
            try ClaudeSettings.change(path: path, adding: command, dryRun: false)
        }
        #expect(ClaudeSettings.registered(settings()).isEmpty)
    }

    @Test func pathsAreQuotedTheWayTheOldScriptQuotedThem() {
        #expect(ClaudeSettings.shellQuoted("/Applications/MicroBridge.app/Contents/MacOS/micro")
            == "/Applications/MicroBridge.app/Contents/MacOS/micro")
        #expect(ClaudeSettings.shellQuoted("/Users/x/a b") == "'/Users/x/a b'")
        #expect(ClaudeSettings.shellQuoted("/Users/x/it's") == "'/Users/x/it'\"'\"'s'")
        #expect(ClaudeSettings.runsBridge("'/Users/x/a b/MicroBridge.app/Contents/MacOS/micro' hook"))
        #expect(!ClaudeSettings.runsBridge("/Applications/MicroBridge.app/Contents/MacOS/micro daemon"))
    }

    @Test func indentedTextIsHowClaudeCodeWritesItsSettings() {
        let value = JSONValue.parseKeepingOrder(#"{"b":[1,{"c":"é"}],"a":{},"z":[],"t":true,"n":null,"x":0.5}"#)
        #expect(value?.indented == """
        {
          "b": [
            1,
            {
              "c": "é"
            }
          ],
          "a": {},
          "z": [],
          "t": true,
          "n": null,
          "x": 0.5
        }
        """)
    }
}

/// The MicroBridge plugin for Claude Code: its hooks match the settings hook, and its script hands
/// each event to the app unless the settings hook already does.
@Suite struct PluginTests {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let home = NSTemporaryDirectory() + "mb-plugin-" + UUID().uuidString

    @Test func thePluginHooksTheSameEventsAsTheSettings() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("plugin/hooks/hooks.json"))
        let hooks = try #require(JSONValue.parseKeepingOrder(String(decoding: data, as: UTF8.self))?["hooks"])
        guard case let .object(events) = hooks else { Issue.record("no hooks"); return }
        #expect(events.map(\.0) == ClaudeSettings.events.map(\.name))
        for (name, matcher) in ClaudeSettings.events {
            #expect((hooks[name].flatMap { if case let .array(g) = $0 { g.first } else { nil } }?["matcher"] != nil) == matcher, "\(name)")
        }
    }

    /// Runs the plugin's script with `home` as the home folder and `input` on stdin.
    func runHook(_ input: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [root.appendingPathComponent("plugin/bin/micro-hook").path]
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(input.utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// A stand-in for the installed app that writes down what it was given.
    func fakeApp() throws -> String {
        let folder = home + "/Applications/MicroBridge.app/Contents/MacOS"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let said = home + "/said"
        try "#!/bin/sh\necho \"$@\" > \(said)\ncat >> \(said)\n".write(toFile: folder + "/micro", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder + "/micro")
        return said
    }

    @Test func thePluginHandsEachEventToTheApp() throws {
        let said = try fakeApp()
        #expect(try runHook(#"{"hook_event_name":"Stop"}"#) == 0)
        #expect(try String(contentsOfFile: said, encoding: .utf8) == "hook\n{\"hook_event_name\":\"Stop\"}")
    }

    @Test func thePluginStaysOutWhenTheSettingsHookIsThere() throws {
        let said = try fakeApp()
        try FileManager.default.createDirectory(atPath: home + "/.claude", withIntermediateDirectories: true)
        let settings = ClaudeSettings.installing("'/Users/x/My Apps/MicroBridge.app/Contents/MacOS/micro' hook", into: .object([]))
        try settings.indented.write(toFile: home + "/.claude/settings.json", atomically: true, encoding: .utf8)
        #expect(try runHook("{}") == 0)
        #expect(!FileManager.default.fileExists(atPath: said), "the settings hook reports, not the plugin")
    }

    @Test func withoutTheAppThePluginDoesNothing() throws {
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        #expect(try runHook("{}") == 0)
    }
}
