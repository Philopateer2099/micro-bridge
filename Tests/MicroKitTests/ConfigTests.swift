import Foundation
import Testing
@testable import MicroKit

@Suite struct CommandTests {
    let claude = "com.anthropic.claudefordesktop"
    let terminal = "com.apple.Terminal"

    func names(_ config: Config, _ control: String, _ trigger: String, _ app: String?) -> [String] {
        config.actions(for: control, trigger, app: app).map(\.description)
    }

    @Test func defaultLayoutMatchesTheStockKeycaps() {
        let config = Config.builtIn
        // Fast, Approve, Decline, Fork, Mic, Send.
        #expect(names(config, "ACT06", "press", claude) == ["text:/fast\\n"])
        #expect(names(config, "ACT07", "press", claude) == ["click:Suggested next actions/first", "click:epitaxy-approval-card/Allow once",
             "click:epitaxy-approval-card/=Next!", "click:epitaxy-approval-card/=Submit!", "key:cmd+return"])
        #expect(names(config, "ACT07", "press", terminal) == ["key:return"])
        #expect(names(config, "ACT08", "press", claude) == ["click:Suggested next actions/2", "click:Suggested next actions^2/Dismiss", "click:epitaxy-approval-card/Deny",
             "click:epitaxy-approval-card/=Skip!", "key:escape"])
        #expect(names(config, "ACT09", "press", claude) == ["key:cmd+opt+o"])
        #expect(names(config, "ACT09", "press", terminal) == ["text:/branch\\n"])
        #expect(names(config, "ACT09", "press", "com.apple.finder") == [])
        #expect(names(config, "ACT12", "press", nil) == ["key:return"])
        // The mic holds its key for as long as the pad key is down.
        // Cmd+D switches dictation on and off, so holding the key means: once down, once up.
        #expect(names(config, "WIDE", "press", claude) == ["key:cmd+d"])
        #expect(names(config, "WIDE", "release", claude) == ["key:cmd+d"])
        #expect(names(config, "WIDE", "press", terminal) == ["keydown:space"])
        #expect(names(config, "WIDE", "release", terminal) == ["keyup:space"])
        // Orca is not one of the pad's apps: a key does nothing there.
        #expect(names(config, "WIDE", "press", "com.stablyai.orca") == [])
        #expect(names(config, "WIDE", "hold", claude) == [])
        // A key that is a command has no double tap unless the command has one.
        #expect(!config.hasDoubleTap("WIDE", app: claude) && !config.hasDoubleTap("ACT07", app: claude))
        // Stick, dial, and an Agent Key with no session.
        #expect(names(config, "STICK", "up", claude) == ["key:cmd+shift+m"])
        #expect(names(config, "STICK", "down", claude) == ["key:cmd+b"])
        #expect(names(config, "STICK", "down", terminal) == [])
        #expect(names(config, "DIAL", "hold", nil).first?.hasPrefix("sh:open -t") == true)
        // A press on a key with no session does nothing unless the config says otherwise.
        #expect(names(config, "AG", "empty", nil) == [])
        // One per stock keycap, and LOCK, which no keycap has.
        #expect(config.commands.count == 49)
    }

    @Test func aKeyTakesAnyCommandByName() throws {
        let config = try Config.parse(#"""
        {"keys": {"ACT09": "cmd:new", "ACT06": {"press": "cmd:TERM", "hold": "key:escape"}},
         "stick": {"right": ["cmd:DIFF", "ack"]}}
        """#)
        #expect(names(config, "ACT09", "press", claude) == ["key:cmd+n"])
        #expect(names(config, "ACT09", "press", terminal) == ["text:/clear\\n"])
        #expect(names(config, "ACT06", "press", claude) == ["key:cmd+j"])
        #expect(names(config, "ACT06", "hold", claude) == ["key:escape"])
        #expect(names(config, "ACT06", "release", claude) == [])
        // A stick direction runs the command's press.
        #expect(names(config, "STICK", "right", claude) == ["key:cmd+shift+d", "ack"])
    }

    @Test func theLockCommandTurnsTheLightsOffAndLocksInAnyApp() throws {
        #expect(Action.parse("lock") == .lock && Action.parse("lock:now") == nil)
        #expect(Action.lock.description == "lock")
        #expect(Action.lock.plainWords == "Turn the lights off and lock the Mac")
        // It types ⌃⌘Q, so a file with it asks for Accessibility.
        #expect(Action.lock.typesKeys)
        let config = try Config.parse(#"{"dial": {"hold": "cmd:LOCK"}}"#)
        #expect(names(config, "DIAL", "hold", claude) == ["lock"])
        #expect(names(config, "DIAL", "hold", terminal) == ["lock"])
        #expect(config.typesKeys)
    }

    @Test func commandsResolveByGroupThenBundleThenDefault() throws {
        let config = try Config.parse(#"""
        {"apps": {"editors": ["dev.zed.Zed"]},
         "commands": {
           "SPLIT": {"editors": "key:cmd+k", "com.apple.finder": ["key:a", "key:b"], "default": "none"},
           "MIC": {"press": "keydown:f5", "release": "keyup:f5"},
           "PLAIN": "text:hi"}}
        """#)
        #expect(names(config, "ACT09", "press", "dev.zed.Zed") == ["key:cmd+k"])
        #expect(names(config, "ACT09", "press", "com.apple.finder") == ["key:a", "key:b"])
        #expect(names(config, "ACT09", "press", claude) == [])
        // A command the file mentions is replaced whole; one given as triggers applies everywhere.
        #expect(names(config, "WIDE", "press", claude) == ["keydown:f5"])
        #expect(names(config, "WIDE", "release", "com.apple.finder") == ["keyup:f5"])
        #expect(config.command("PLAIN", app: nil)?["press"]?.map(\.description) == ["text:hi"])
        // Commands the file leaves out keep their defaults.
        #expect(names(config, "ACT07", "press", claude) == ["click:Suggested next actions/first", "click:epitaxy-approval-card/Allow once",
             "click:epitaxy-approval-card/=Next!", "click:epitaxy-approval-card/=Submit!", "key:cmd+return"])
    }

    @Test func reportsBadCommands() {
        func problems(_ text: String) -> [String] {
            do { _ = try Config.parse(text); return [] } catch { return error.problems }
        }
        #expect(problems(#"{"keys": {"ACT09": "cmd:NOPE"}}"#).contains { $0.contains("no command named NOPE") })
        #expect(problems(#"{"commands": {"X": {"nowhere": "key:a"}}}"#).contains { $0.contains("no app group") })
        #expect(problems(#"{"commands": {"X": {"default": "cmd:FAST"}}}"#).contains { $0.contains("cannot use cmd:") })
        #expect(problems(#"{"commands": {"bad name": "key:a"}}"#).contains { $0.contains("a name is") })
        #expect(problems(#"{"commands": {"X": {"default": {"tap": "key:a"}}}}"#).contains { $0.contains("unknown entry") })
        #expect(problems(#"{"apps": {"claude": "x"}}"#).contains { $0.contains("expected a list") })
        #expect(Action.parse("cmd:mind+") == .command("MIND+") && Action.parse("cmd:") == nil)
        #expect(Action.parse("cmd:a b") == nil)
    }

    @Test func anEmptyKeyHoldsItsPlaceForTheNextSession() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: nil, cwd: nil))
        state.reserve(0) // taken: nothing to hold
        #expect(state.reserved == nil)
        state.reserve(4)
        state.apply(.report(session: "a", status: .done, pid: nil, cwd: nil)) // not a new session
        #expect(state.reserved == 4)
        state.apply(.report(session: "b", status: .idle, pid: nil, cwd: nil))
        #expect(state.owner(of: 4)?.id == "b" && state.reserved == nil)
        state.apply(.report(session: "c", status: .idle, pid: nil, cwd: nil))
        #expect(state.owner(of: 1)?.id == "c")
    }
}

@Suite struct ConfigTests {
    func names(_ config: Config, _ control: String, _ trigger: String) -> [String] {
        config.actions(for: control, trigger).map(\.description)
    }

    @Test func builtInDefaults() {
        let config = Config.builtIn
        #expect(names(config, "AG", "press") == ["ack", "jump", "pane:chat"])
        #expect(names(config, "AG", "doubleTap") == [])
        #expect(names(config, "ACT06", "press") == ["text:/fast\\n"])
        #expect(names(config, "ACT07", "press") == ["key:return"])
        #expect(names(config, "ACT09", "press") == [])
        #expect(config.actions(for: "STICK", "up", app: "com.apple.Terminal").map(\.description) == ["key:shift+tab"])
        #expect(names(config, "DIAL", "ccw") == ["key:down"] && names(config, "DIAL", "cw") == ["key:up"])
        #expect(config.lighting.brightness == 1 && config.lighting.autoDimSeconds == 0)
        #expect(config.typesKeys && !config.hasDoubleTap("AG") && !config.hasDoubleTap("ACT07"))
    }

    @Test func aMentionedControlDoesOnlyWhatTheFileSays() throws {
        let config = try Config.parse(#"""
        {"keys": {"ACT09": ["sh:git status", "focus"],
                  "WIDE": {"press": "keydown:space", "release": "keyup:space"},
                  "ACT07": "none"},
         "agentKeys": {"press": "focus"},
         "dial": {"cw": "key:cmd+]"}}
        """#)
        #expect(names(config, "ACT09", "press") == ["sh:git status", "focus"])
        #expect(names(config, "WIDE", "press") == ["keydown:space"])
        #expect(names(config, "WIDE", "release") == ["keyup:space"])
        #expect(names(config, "ACT07", "press") == [])
        #expect(names(config, "AG", "press") == ["focus"] && names(config, "AG", "doubleTap") == [])
        #expect(names(config, "DIAL", "cw") == ["key:cmd+]"] && names(config, "DIAL", "press") == [])
        // Not mentioned: still the default.
        #expect(names(config, "ACT08", "press") == ["key:escape"])
        #expect(config.actions(for: "STICK", "up", app: "com.apple.Terminal").map(\.description) == ["key:shift+tab"])
    }

    @Test func readsLighting() throws {
        let config = try Config.parse(#"""
        {"lighting": {"brightness": 40, "autoDimSeconds": 180, "pulseSelected": true,
                      "colors": {"working": "#00FFFF"}},
         "keystrokeApps": ["com.apple.Terminal"]}
        """#)
        #expect(config.lighting.brightness == 0.4 && config.lighting.autoDimSeconds == 180)
        #expect(config.lighting.pulseSelected)
        #expect(config.lighting.color(.working) == 0x00FFFF && config.lighting.color(.done) == 0x00FF4C)
        #expect(config.keystrokeApps == ["com.apple.Terminal"])
    }

    @Test func catchingTheLockShortcutIsOffUnlessAsked() throws {
        #expect(!Config.builtIn.lighting.offWhenLocked)
        #expect(try !Config.parse(Config.defaultFileText).lighting.offWhenLocked)
        #expect(try Config.parse(#"{"lighting": {"offWhenLocked": true}}"#).lighting.offWhenLocked)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"lighting": {"offWhenLocked": "yes"}}"#) }
    }

    @Test func onlyControlCommandQIsTheLockShortcut() {
        #expect(LockShortcut.isLockShortcut([.maskControl, .maskCommand]))
        // Caps Lock or the Fn key held down still locks.
        #expect(LockShortcut.isLockShortcut([.maskControl, .maskCommand, .maskAlphaShift, .maskSecondaryFn]))
        #expect(!LockShortcut.isLockShortcut([.maskCommand]))
        #expect(!LockShortcut.isLockShortcut([.maskControl]))
        #expect(!LockShortcut.isLockShortcut([.maskControl, .maskCommand, .maskShift]))
        #expect(!LockShortcut.isLockShortcut([.maskControl, .maskCommand, .maskAlternate]))
        #expect(KeyCombo.parse("q")?.code == UInt16(LockShortcut.q))
    }

    @Test func readsClickGuard() throws {
        #expect(Config.builtIn.clickGuard == 1)
        #expect(try Config.parse(#"{"clickGuard": 0}"#).clickGuard == 0)
        #expect(try Config.parse(#"{"clickGuard": 2.5}"#).clickGuard == 2.5)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"clickGuard": -1}"#) }
        #expect(throws: ConfigError.self) { try Config.parse(#"{"clickGuard": "long"}"#) }
    }

    /// Out of the box the bridge has one layer, for the Claude app and terminals, and nothing
    /// is kept apart.
    @Test func readsTheBridgesOwnLayers() throws {
        #expect(Config.builtIn.layerApps == [1: ["claude", "terminal"]])
        #expect(try Config.parse(Config.defaultFileText).layerApps == Config.builtIn.layerApps)
        #expect(Config.builtIn.ownLayers.isEmpty)
        #expect(Config.builtIn.layer(ofApp: "com.anthropic.claudefordesktop") == 1)
        #expect(Config.builtIn.layer(ofApp: "com.mitchellh.ghostty") == 1)
        #expect(Config.builtIn.layer(ofApp: "com.apple.Safari") == nil)

        // A layer the file leaves out keeps its apps.
        let config = try Config.parse(#"{"apps": {"orca": ["com.stablyai.orca"]}, "layerApps": {"2": ["orca"]}}"#)
        #expect(config.layerApps == [1: ["claude", "terminal"], 2: ["orca"]])
        #expect(config.ownLayers == [2])
        #expect(config.isOwn(layer: 1) && config.isOwn(layer: 2) && !config.isOwn(layer: 3))
        #expect(config.apps(onLayer: 2) == ["com.stablyai.orca"])
        #expect(config.layer(ofApp: "com.stablyai.orca") == 2)
        #expect(config.layer(ofApp: "com.anthropic.claudefordesktop") == 1)
        // A bundle id needs no group.
        #expect(try Config.parse(#"{"layerApps": {"2": ["com.stablyai.orca"]}}"#).layer(ofApp: "com.stablyai.orca") == 2)
        // A layer with no app is still the bridge's own.
        #expect(try Config.parse(#"{"layerApps": {"2": []}}"#).ownLayers == [2])
        // The first layer's apps are the file's to change.
        #expect(try Config.parse(#"{"layerApps": {"1": ["claude"]}}"#).layer(ofApp: "com.mitchellh.ghostty") == nil)
    }

    /// A layer's app that `keystrokeApps` leaves out gets no key and no click from the pad, so a
    /// config that loads says so (D-067). Seen on the pad on 2026-11-24: Approve did nothing in
    /// Orca, which had layer 2 and was not in the owner's list.
    @Test func aLayersAppThatTheTypingListLeavesOutIsWarnedAbout() throws {
        // An empty list means whichever app is in front: nothing to say.
        #expect(try Config.parse(#"{"layerApps": {"2": ["orca"]}}"#).warnings.isEmpty)

        let missing = try Config.parse(#"{"keystrokeApps": ["com.anthropic.claudefordesktop"], "layerApps": {"2": ["orca"]}}"#)
        #expect(missing.layerAppsNotTypedIn.map(\.layer) == [2])
        #expect(missing.layerAppsNotTypedIn.map(\.app) == ["com.stablyai.orca"])
        #expect(missing.warnings.count == 1)
        #expect(missing.warnings.first?.contains("layerApps.2: com.stablyai.orca is not in keystrokeApps") == true)

        let listed = try Config.parse(
            #"{"keystrokeApps": ["com.anthropic.claudefordesktop", "com.stablyai.orca"], "layerApps": {"2": ["orca"]}}"#)
        #expect(listed.warnings.isEmpty)

        // The first layer's apps are the built-in ones: a list that leaves a terminal out is a choice.
        #expect(try Config.parse(#"{"keystrokeApps": ["com.anthropic.claudefordesktop"]}"#).warnings.isEmpty)
    }

    @Test func turnsDownOwnLayersThatCannotWork() {
        func problems(_ text: String) -> [String] {
            do { _ = try Config.parse(text); return [] } catch { return error.problems }
        }
        #expect(problems(#"{"layerApps": ["orca"]}"#).contains { $0.contains("layerApps: expected an object") })
        #expect(problems(#"{"layerApps": {"0": []}}"#).contains { $0.contains("expected a layer from 1 to 9") })
        #expect(problems(#"{"layerApps": {"two": []}}"#).contains { $0.contains("expected a layer from 1 to 9") })
        #expect(problems(#"{"layerApps": {"2": "orca"}}"#).contains { $0.contains("expected a list of app groups or bundle ids") })
        #expect(problems(#"{"layerApps": {"2": [""]}}"#).contains { $0.contains("expected a list of app groups or bundle ids") })
        #expect(problems(#"{"layerApps": {"2": ["notes"]}}"#).contains { $0.contains("notes: no app group with that name") })
        // Orca's group is built in.
        #expect(problems(#"{"layerApps": {"2": ["orca"]}}"#).isEmpty)
        // A layer is the bridge's own or another app's.
        #expect(problems(#"{"layers": {"2": "com.openai.codex"}, "layerApps": {"2": ["com.stablyai.orca"]}}"#)
            .contains { $0.contains("layers gives this layer to com.openai.codex") })
        // An app belongs to one layer.
        #expect(problems(#"{"layerApps": {"2": ["claude"]}}"#)
            .contains { $0.contains("com.anthropic.claudefordesktop is on layer 1 already") })
        #expect(problems(#"{"layers": {"3": "com.openai.codex"}, "layerApps": {"2": ["com.stablyai.orca"]}}"#).isEmpty)
    }

    @Test func readsLayerWarning() throws {
        #expect(Config.builtIn.layerWarning)
        #expect(try Config.parse(Config.defaultFileText).layerWarning)
        #expect(try !Config.parse(#"{"layerWarning": false}"#).layerWarning)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"layerWarning": "no"}"#) }
    }

    @Test func readsBatteryWarning() throws {
        #expect(Config.builtIn.batteryWarning == 20)
        #expect(try Config.parse(Config.defaultFileText).batteryWarning == 20)
        #expect(try Config.parse(#"{"batteryWarning": 0}"#).batteryWarning == 0)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"batteryWarning": 150}"#) }
        #expect(throws: ConfigError.self) { try Config.parse(#"{"batteryWarning": true}"#) }
    }

    @Test func readsRememberHours() throws {
        #expect(Config.builtIn.rememberHours == .infinity)
        #expect(try Config.parse(Config.defaultFileText).rememberHours == .infinity)
        #expect(try Config.parse(#"{"rememberHours": "always"}"#).rememberHours == .infinity)
        #expect(try Config.parse(#"{"rememberHours": 24}"#).rememberHours == 24)
        #expect(try Config.parse(#"{"rememberHours": 0}"#).rememberHours == 0)
        #expect(try Config.parse(#"{"rememberHours": 1.5}"#).rememberHours == 1.5)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"rememberHours": -1}"#) }
        #expect(throws: ConfigError.self) { try Config.parse(#"{"rememberHours": "a day"}"#) }
    }

    @Test func readsUrgentFirst() throws {
        #expect(Config.builtIn.urgentFirst)
        #expect(try Config.parse(Config.defaultFileText).urgentFirst)
        #expect(try !Config.parse(#"{"urgentFirst": false}"#).urgentFirst)
        // The switch's older name still works.
        #expect(try !Config.parse(#"{"needsYouFirst": false}"#).urgentFirst)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"urgentFirst": "no"}"#) }
    }

    @Test func aClickRuleMayAskForTheWholeLabel() throws {
        let rule = try #require(ButtonRule.parse("epitaxy-approval-card/=Next!"))
        #expect(rule.insist && rule.pick == .exactly("Next") && rule.spelling == "epitaxy-approval-card/=Next!")
        // On a card's last question there is no "Next", and "Show next question" must not stand in for it.
        #expect(rule.choose(from: ["Show previous question", "Show next question", "Skip", "Submit"]) == nil)
        #expect(rule.choose(from: ["Show next question", "Skip", "next"]) == 2)
        // A plain label settles for a button that only contains it.
        #expect(ButtonRule(box: "b", pick: .label("Next")).choose(from: ["Show next question", "Skip"]) == 0)
        #expect(ButtonRule.parse("box/=") == nil && ButtonRule.parse("box/=!") == nil)
    }

    @Test func aChoiceRuleMayNameSeveralButtonsAfterItsOptions() throws {
        let rule = try #require(OptionRule.parse("epitaxy-approval-card/epitaxy-answer-option+Next|Submit/next"))
        #expect(rule.thens == ["next", "submit"])
        #expect(rule.spelling == "epitaxy-approval-card/epitaxy-answer-option+Next|Submit/next")
        #expect(OptionRule.parse("box/opt+Submit/prev")?.thens == ["submit"])
        #expect(OptionRule.parse("box/opt/mark")?.thens == [])
    }

    @Test func reportsEveryProblem() {
        let text = #"""
        {"keys": {"ACT07": "key:bogus", "NOPE": "ack", "ACT08": {"tap": "ack"}},
         "stick": "ack", "lighting": {"brightness": 300, "colors": {"off": "#000000", "idle": "red"}},
         "extra": 1}
        """#
        #expect(throws: ConfigError.self) { try Config.parse(text) }
        do {
            _ = try Config.parse(text)
        } catch {
            #expect(error.problems.count == 8, "\(error.description)")
            #expect(error.description.contains("keys.ACT07"))
            #expect(error.description.contains("lighting.brightness"))
        }
        #expect(throws: ConfigError.self) { try Config.parse("[]") }
    }

    @Test func parsesKeyCombos() {
        let combo = KeyCombo.parse("Cmd+Shift+P")
        #expect(combo?.code == 35 && combo?.command == true && combo?.shift == true && combo?.option == false)
        #expect(KeyCombo.parse("escape")?.code == 53)
        #expect(KeyCombo.parse("ctrl+alt+f12")?.control == true)
        #expect(KeyCombo.parse("bogus") == nil && KeyCombo.parse("hyper+a") == nil && KeyCombo.parse("shift+") == nil)
    }

    @Test func actionsRoundTrip() {
        for text in ["ack", "jump", "focus", "key:shift+tab", "keydown:space", "keyup:space", "text:/fast\\n",
                     "sh:git status --short", "open:https://example.com", "click:step-in/first",
                     "click:step-in/last", "click:box/2", "click:*/Allow once",
                     "click:Suggested next actions^2/Dismiss",
                     "choose:epitaxy-approval-card/epitaxy-answer-option/next", "choose:box/group/opt/prev",
                     "click:box/=Next!", "choose:box/opt+Next|Submit/next", "complete:Prompt"] {
            let unescaped = text.replacingOccurrences(of: "\\n", with: "\n")
            #expect(Action.parse(unescaped)?.description == text)
        }
        #expect(Action.parse("none") == Action.none)
        for bad in ["", "nope", "key:", "text:", "sh:  ", "ack:1", "focus:now", "jump:there",
                    "click:", "click:first", "click:/first", "click:box/", "click:box/0",
                    "click:box^0/first", "click:box^9/first", "click:box^x/first", "click:*^2/first",
                    "choose:box/next", "choose:box/opt/sideways", "choose:/opt/next", "choose:*/opt/next",
                    "complete:", "complete:  "] {
            #expect(Action.parse(bad) == nil, "\(bad)")
        }
        #expect(Action.parse("text: two words")?.description == "text: two words")
    }

    @Test func aClickRulePicksItsButton() throws {
        let labels = ["Yes, fix it", "Not now", "Dismiss"]
        func pick(_ text: String) -> Int? { ButtonRule.parse(text)?.choose(from: labels) }
        #expect(pick("box/first") == 0 && pick("box/last") == 2 && pick("box/2") == 1)
        #expect(pick("box/4") == nil)
        // A whole label wins over a label that only contains the text.
        #expect(pick("box/dismiss") == 2 && pick("box/not") == 1 && pick("box/nope") == nil)
        #expect(ButtonRule.parse("box/first")?.choose(from: []) == nil)
        #expect(ButtonRule.parse("box/last")?.choose(from: []) == nil)
    }

    @Test func aClickRuleKnowsItsBox() throws {
        let byClass = try #require(ButtonRule.parse("Epitaxy-Approval-Card/Deny"))
        #expect(byClass.isBox(id: nil, label: "Permission request", classes: ["epitaxy-approval-card", "relative"]))
        #expect(byClass.isBox(id: "epitaxy-approval-card", label: nil, classes: []))
        // A class that only refers to the box is not the box.
        #expect(!byClass.isBox(id: nil, label: nil, classes: ["has-[.epitaxy-approval-card]:shrink", "p-4"]))
        // A label counts only as a whole: a chat that mentions the box must not become one.
        let byLabel = try #require(ButtonRule.parse("suggested next actions^2/Dismiss"))
        #expect(byLabel.reach == 2 && byLabel.box == "suggested next actions")
        #expect(byLabel.isBox(id: nil, label: "Suggested next actions", classes: ["flex"]))
        #expect(!byLabel.isBox(id: nil, label: "About the Suggested next actions box", classes: []))
        // A star means anywhere in the window.
        #expect(try #require(ButtonRule.parse("*/Allow once")).isBox(id: nil, label: nil, classes: []))
    }

    @Test func enterSendsTheSuggestionOnlyInClaude() {
        #expect(Config.builtIn.actions(for: "ACT12", "press", app: "com.anthropic.claudefordesktop").map(\.description)
            == ["complete:Prompt", "key:return"])
        #expect(Config.builtIn.actions(for: "ACT12", "press", app: "com.apple.Terminal").map(\.description) == ["key:return"])
    }

    @Test func aSuggestionCountsOnlyInABoxWithNothingTyped() {
        typealias Field = ScreenButtons.Field
        #expect(Field(text: "\n", placeholder: "Type / for commands", ghost: "Run the tests").suggestion == "Run the tests")
        // Some boxes count their ghost text in their value.
        #expect(Field(text: "Run the tests", placeholder: nil, ghost: " Run the tests ").suggestion == "Run the tests")
        // Typed text wins: the ghost is a typeahead for it, not a prompt to send.
        #expect(Field(text: "Run", placeholder: nil, ghost: " the tests").suggestion == nil)
        // A hint alone is never sent.
        #expect(Field(text: "\n", placeholder: "Type / for commands").suggestion == nil)
        #expect(Field(text: "", placeholder: nil, ghost: "  \n").suggestion == nil)
    }

    @Test func onlyAnEmptyBoxWithoutItsHintAsksForTab() {
        typealias Field = ScreenButtons.Field
        // The Claude app drops its hint while a suggestion it does not expose stands in its place.
        #expect(Field(text: "\n", placeholder: nil).hidesHint)
        #expect(!Field(text: "\n", placeholder: "Type / for commands").hidesHint)
        #expect(!Field(text: "commit it", placeholder: nil).hidesHint)
        // A readable suggestion is typed instead.
        #expect(!Field(text: "\n", placeholder: nil, ghost: "commit it").hidesHint)
    }

    @Test func approveAndDeclineAnswerTheNextStepBoxBeforeTheyType() throws {
        let claude = "com.anthropic.claudefordesktop"
        #expect(Config.builtIn.actions(for: "ACT07", "press", app: claude).map(\.description)
            == ["click:Suggested next actions/first", "click:epitaxy-approval-card/Allow once",
             "click:epitaxy-approval-card/=Next!", "click:epitaxy-approval-card/=Submit!", "key:cmd+return"])
        // Decline takes the box's second choice; with only one, it dismisses the box.
        #expect(Config.builtIn.actions(for: "ACT08", "press", app: claude).map(\.description)
            == ["click:Suggested next actions/2", "click:Suggested next actions^2/Dismiss", "click:epitaxy-approval-card/Deny",
             "click:epitaxy-approval-card/=Skip!", "key:escape"])
        #expect(Config.builtIn.actions(for: "ACT07", "press", app: "com.example.other").map(\.description) == ["key:return"])
        #expect(Config.builtIn.actions(for: "ACT08", "press", app: "com.example.other").map(\.description) == ["key:escape"])
    }

    @Test func aClickRuleMayInsist() throws {
        let rule = try #require(ButtonRule.parse("epitaxy-approval-card/Submit!"))
        #expect(rule.insist && rule.pick == .label("Submit") && rule.spelling == "epitaxy-approval-card/Submit!")
        let plain = try #require(ButtonRule.parse("box^2/first"))
        #expect(!plain.insist && plain.spelling == "box^2/first")
        #expect(ButtonRule.parse("box/first!")?.pick == .first && ButtonRule.parse("box/!") == nil)
    }

    @Test func aChoiceMovesOneStepAndStopsAtTheEnds() {
        #expect(OptionRule.target(on: [true, false, false], step: .next) == 1)
        #expect(OptionRule.target(on: [false, true, false], step: .prev) == 0)
        #expect(OptionRule.target(on: [false, false, true], step: .next) == nil)
        #expect(OptionRule.target(on: [true, false, false], step: .prev) == nil)
        // Nothing on yet: start at the near end.
        #expect(OptionRule.target(on: [false, false, false], step: .next) == 0)
        #expect(OptionRule.target(on: [false, false, false], step: .prev) == 2)
        #expect(OptionRule.target(on: [], step: .next) == nil)
    }

    @Test func aChoiceRuleNamesTheButtonAfterItsOptions() throws {
        let rule = try #require(OptionRule.parse("epitaxy-approval-card/epitaxy-answer-option+Submit/next"))
        #expect(rule.option == "epitaxy-answer-option" && rule.then == "Submit" && rule.step == .next)
        #expect(rule.spelling == "epitaxy-approval-card/epitaxy-answer-option+Submit/next")
        let mark = try #require(OptionRule.parse("box/opt/mark"))
        #expect(mark.step == .mark && mark.then == nil && mark.spelling == "box/opt/mark")
        #expect(OptionRule.parse("box/opt+/next") == nil)
        // Marking is not a move.
        #expect(OptionRule.target(on: [true, false], step: .mark) == nil)
    }

    @Test func theHighlightMovesOverTheStopsAndSkipsTheRest() {
        // Places 0 to 2 are answers, 3 is "Other", 4 is "Skip", 5 is "Submit".
        let stops = [0, 1, 2, 5]
        // The focus is outside the card: start at the top, whichever way the dial turns.
        #expect(OptionRule.stop(stops, from: nil, step: .next) == 0)
        #expect(OptionRule.stop(stops, from: nil, step: .prev) == 0)
        #expect(OptionRule.stop(stops, from: 0, step: .next) == 1)
        // Past the last answer comes Submit, not "Other" or "Skip".
        #expect(OptionRule.stop(stops, from: 2, step: .next) == 5)
        #expect(OptionRule.stop(stops, from: 5, step: .prev) == 2)
        // The ends do not wrap.
        #expect(OptionRule.stop(stops, from: 5, step: .next) == nil)
        #expect(OptionRule.stop(stops, from: 0, step: .prev) == nil)
        // From a place that is not a stop, go to the nearest stop that way.
        #expect(OptionRule.stop(stops, from: 4, step: .next) == 5 && OptionRule.stop(stops, from: 3, step: .prev) == 2)
        #expect(OptionRule.stop(stops, from: 1, step: .mark) == nil)
    }

    @Test func aFastSecondStepStartsFromTheOptionJustTurnedOn() {
        // The app still shows the first option on; the caller turned on the second a moment ago.
        #expect(OptionRule.target(on: [true, false, false, false], step: .next, assuming: 1) == 2)
        #expect(OptionRule.target(on: [true, false, false, false], step: .prev, assuming: 1) == 0)
        #expect(OptionRule.target(on: [true, false, false, false], step: .next, assuming: 3) == nil)
        // A place the card no longer has is ignored.
        #expect(OptionRule.target(on: [true, false], step: .next, assuming: 5) == 1)
    }

    @Test func theDialChoosesOnACardAndScrollsElsewhere() {
        let claude = "com.anthropic.claudefordesktop"
        func dial(_ trigger: String, _ app: String?) -> [String] {
            Config.builtIn.actions(for: "DIAL", trigger, app: app).map(\.description)
        }
        // On the pad a turn to the right arrives as `ccw`.
        #expect(dial("ccw", claude) == ["choose:epitaxy-approval-card/epitaxy-answer-option+Next|Submit/next", "key:down"])
        #expect(dial("cw", claude) == ["choose:epitaxy-approval-card/epitaxy-answer-option+Next|Submit/prev", "key:up"])
        // The press marks the highlighted answer where several may be picked; otherwise it submits.
        #expect(dial("press", claude) == ["choose:epitaxy-approval-card/epitaxy-answer-option/mark",
                                          "click:epitaxy-approval-card/=Next!", "click:epitaxy-approval-card/=Submit!",
                                          "key:return"])
        #expect(dial("ccw", "com.example.other") == ["key:down"] && dial("press", nil) == ["key:return"])
    }

    @Test func defaultFileIsValidAndComplete() throws {
        #expect(try Config.parse(Config.defaultFileText, base: Config()) == Config.builtIn)
        #expect(try Config.parse("{}") == Config.builtIn)
    }

    @Test func lightsFollowSettings() {
        var state = BridgeState()
        state.apply(.report(session: "a", status: .working, pid: nil, cwd: nil))
        state.apply(.report(session: "b", status: .done, pid: nil, cwd: nil))
        var lighting = Config.Lighting()
        lighting.brightness = 0.25
        lighting.colors[.working] = 0x123456
        let lights = state.lights(lighting, selected: [1])
        #expect(lights[0].color == 0x123456 && lights[0].brightness == 0.25 && lights[0].effect == .solid)
        #expect(lights[1].color == 0x00FF4C && lights[1].effect == .breath)
        #expect(lights[2].effect == .off)
        #expect(state.lights(lighting, dimmed: true).allSatisfy { $0.effect == .off })
        #expect(state.lights(Config.Lighting()) == state.lights)
    }
}

@Suite struct GestureTests {
    func key(_ name: String, _ action: Int) -> PadEvent { .key(name: name, action: action, agent: nil) }
    func names(_ fired: [Gestures.Fired]) -> [String] {
        fired.map { "\($0.control).\($0.trigger)" + ($0.slot.map { "#\($0)" } ?? "") }
    }

    @Test func pressAndRelease() {
        var g = Gestures()
        #expect(names(g.handle(key("ACT07", 1), at: 0) { _ in false }) == ["ACT07.press"])
        #expect(g.hasKeysDown)
        #expect(names(g.handle(key("ACT07", 1), at: 0.1) { _ in false }) == [])
        #expect(names(g.handle(key("ACT07", 0), at: 0.2) { _ in false }) == ["ACT07.release"])
        #expect(names(g.handle(key("ACT07", 0), at: 0.3) { _ in false }) == [])
        #expect(!g.hasKeysDown)
    }

    @Test func agentKeysShareOneControlAndCarryTheirSlot() {
        var g = Gestures()
        #expect(names(g.handle(key("AG03", 1), at: 0) { _ in false }) == ["AG.press#3"])
        #expect(names(g.handle(key("AG03", 0), at: 0.1) { _ in false }) == ["AG.release#3"])
    }

    @Test func doubleTapNeedsABindingAndASecondPressInTime() {
        var g = Gestures()
        let bound: (String) -> Bool = { $0 == "AG" }
        _ = g.handle(key("AG00", 1), at: 0, hasDoubleTap: bound)
        _ = g.handle(key("AG00", 0), at: 0.1, hasDoubleTap: bound)
        #expect(names(g.handle(key("AG00", 1), at: 0.3, hasDoubleTap: bound)) == ["AG.doubleTap#0"])
        _ = g.handle(key("AG00", 0), at: 0.35, hasDoubleTap: bound)
        // A third quick press starts over.
        #expect(names(g.handle(key("AG00", 1), at: 0.5, hasDoubleTap: bound)) == ["AG.press#0"])
        _ = g.handle(key("AG00", 0), at: 0.6, hasDoubleTap: bound)
        // Too slow.
        #expect(names(g.handle(key("AG00", 1), at: 1.2, hasDoubleTap: bound)) == ["AG.press#0"])
        // Another key in between does not count, and unbound controls only ever press.
        _ = g.handle(key("ACT07", 1), at: 2, hasDoubleTap: bound)
        _ = g.handle(key("ACT07", 0), at: 2.05, hasDoubleTap: bound)
        #expect(names(g.handle(key("ACT07", 1), at: 2.1, hasDoubleTap: bound)) == ["ACT07.press"])
    }

    @Test func aKeyThatWaitsForAHoldPressesWhenItComesUp() {
        var g = Gestures()
        let waits: (String) -> Bool = { $0 == "AG" }
        // A tap: nothing on the way down, press and release on the way up.
        #expect(names(g.handle(key("AG01", 1), at: 0, waitsForHold: waits) { _ in false }) == [])
        #expect(names(g.tick(at: 0.2)) == [])
        #expect(names(g.handle(key("AG01", 0), at: 0.2, waitsForHold: waits) { _ in false }) == ["AG.press#1", "AG.release#1"])
        // A hold: the hold alone, then the release.
        #expect(names(g.handle(key("AG01", 1), at: 5, waitsForHold: waits) { _ in false }) == [])
        #expect(names(g.tick(at: 5.5)) == ["AG.hold#1"])
        #expect(names(g.handle(key("AG01", 0), at: 5.8, waitsForHold: waits) { _ in false }) == ["AG.release#1"])
        // Other controls press on the way down, as before.
        #expect(names(g.handle(key("ACT07", 1), at: 9, waitsForHold: waits) { _ in false }) == ["ACT07.press"])
    }

    @Test func holdingAnAgentKeyForgetsItsSession() throws {
        #expect(Action.parse("forget") == .forget)
        #expect(Config.builtIn.actions(for: "AG", "hold") == [.forget])
        #expect(try Config.parse(Config.defaultFileText).actions(for: "AG", "hold") == [.forget])
    }

    @Test func holdFiresOncePerPress() {
        var g = Gestures()
        _ = g.handle(key("ENC_CLK", 1), at: 10) { _ in false }
        #expect(names(g.tick(at: 10.3)) == [])
        #expect(names(g.tick(at: 10.5)) == ["DIAL.hold"])
        #expect(names(g.tick(at: 11)) == [])
        #expect(names(g.handle(key("ENC_CLK", 0), at: 11.1) { _ in false }) == ["DIAL.release"])
        _ = g.handle(key("AG02", 1), at: 20) { _ in false }
        _ = g.handle(key("AG02", 0), at: 20.2) { _ in false }
        #expect(names(g.tick(at: 21)) == [])
    }

    @Test func wideKeyIsOneControlOverTwoSwitches() {
        var g = Gestures()
        #expect(names(g.handle(key("ACT10", 1), at: 0) { _ in false }) == ["ACT10.press", "WIDE.press"])
        #expect(names(g.handle(key("ACT11", 1), at: 0.01) { _ in false }) == ["ACT11.press"])
        #expect(names(g.handle(key("ACT10", 0), at: 0.5) { _ in false }) == ["ACT10.release"])
        #expect(names(g.handle(key("ACT11", 0), at: 0.51) { _ in false }) == ["ACT11.release", "WIDE.release"])
    }

    @Test func dialTurnsAndPresses() {
        var g = Gestures()
        #expect(names(g.handle(key("ENC_CW", 2), at: 0) { _ in false }) == ["DIAL.cw"])
        #expect(names(g.handle(key("ENC_CC", 2), at: 0) { _ in false }) == ["DIAL.ccw"])
        #expect(names(g.handle(key("ENC_CC", 1), at: 0) { _ in false }) == [])
        #expect(!g.hasKeysDown)
        #expect(names(g.handle(key("ENC_CLK", 1), at: 0) { _ in false }) == ["DIAL.press"])
    }

    @Test func stickFiresOncePerPush() {
        var g = Gestures()
        func stick(_ angle: Double, _ distance: Double) -> [String] {
            names(g.handle(.joystick(angle: angle, distance: distance), at: 0) { _ in false })
        }
        #expect(stick(0.75, 0.2) == [])
        #expect(stick(0.75, 0.6) == ["STICK.up"])
        #expect(stick(0.76, 1.0) == [])
        #expect(stick(0.5, 1.0) == [])         // rolled sideways without letting go
        #expect(stick(0.5, 0.4) == [])         // not back at the center yet
        #expect(stick(0, 0) == [])
        #expect(stick(0.5, 0.9) == ["STICK.left"])
        #expect(Gestures.direction(angle: 0.25, distance: 1) == "down")
        #expect(Gestures.direction(angle: 0.95, distance: 1) == "right")
        #expect(Gestures.direction(angle: 0.05, distance: 1) == "right")
        #expect(Gestures.direction(angle: 0.75, distance: 0.49) == nil)
    }

    @Test func theStickScrollsFasterTheFartherItIsPushed() throws {
        // Near the center, and pushed sideways, it does not scroll.
        #expect(StickScroll.speed(angle: 0.75, distance: 0.1) == nil)
        #expect(StickScroll.speed(angle: 0.5, distance: 1) == nil)
        #expect(StickScroll.speed(angle: 0, distance: 1) == nil)
        let up = try #require(StickScroll.speed(angle: 0.75, distance: 1))
        let down = try #require(StickScroll.speed(angle: 0.25, distance: 1))
        #expect(up == StickScroll.fastest && down == -StickScroll.fastest)
        let barely = try #require(StickScroll.speed(angle: 0.75, distance: StickScroll.deadZone + 0.001))
        #expect(barely > StickScroll.slowest && barely < StickScroll.slowest + 1)
        let half = try #require(StickScroll.speed(angle: 0.7, distance: 0.5))
        #expect(half > barely && half < up / 4)
        // The pad can report past full.
        #expect(StickScroll.speed(angle: 0.75, distance: 1.2) == StickScroll.fastest)
    }

    @Test func aSlowScrollKeepsItsFractions() {
        var scroll = StickScroll()
        // 30 points a second at 60 steps a second: a point every other step.
        let steps = (0 ..< 6).map { _ in scroll.step(speed: 30, seconds: 1.0 / 60) }
        #expect(steps.reduce(0, +) == 3 && steps.allSatisfy { $0 == 0 || $0 == 1 })
        #expect(scroll.step(speed: -600, seconds: 0.1) == -60)
        scroll.reset()
        #expect(scroll.step(speed: 59, seconds: 1.0 / 60) == 0)
    }

    @Test func theStickMovesThePointerToTheNextPane() {
        let sidebar = CGRect(x: 0, y: 0, width: 300, height: 1000)
        let chat = CGRect(x: 300, y: 0, width: 700, height: 1000)
        let web = CGRect(x: 1000, y: 0, width: 400, height: 1000)
        let panes = [web, sidebar, chat]
        let inChat = CGPoint(x: 600, y: 500)
        #expect(Panes.next(from: inChat, in: panes, left: true) == sidebar)
        #expect(Panes.next(from: inChat, in: panes, left: false) == web)
        // At the window's edge it stays.
        #expect(Panes.next(from: CGPoint(x: 1200, y: 500), in: panes, left: false) == nil)
        #expect(Panes.next(from: CGPoint(x: 100, y: 500), in: panes, left: true) == nil)
        // From outside every pane (another screen, the message box): the nearest that way,
        // else the largest.
        #expect(Panes.next(from: CGPoint(x: 1300, y: -400), in: panes, left: true) == web)
        #expect(Panes.next(from: CGPoint(x: 1500, y: -400), in: panes, left: false) == chat)
        // Two panes stacked on the right: the one level with the pointer.
        let top = CGRect(x: 1000, y: 0, width: 400, height: 500)
        let bottom = CGRect(x: 1000, y: 500, width: 400, height: 500)
        #expect(Panes.next(from: CGPoint(x: 600, y: 700), in: [chat, top, bottom], left: false) == bottom)
        #expect(Panes.next(from: inChat, in: [], left: true) == nil)
        // A hidden browser tab under the one on show is not the next pane.
        let hiddenTab = web.offsetBy(dx: 0.5, dy: 0)
        #expect(Panes.next(from: CGPoint(x: 1200, y: 500), in: panes + [hiddenTab], left: false) == nil)
        #expect(Panes.next(from: CGPoint(x: 1200, y: 500), in: panes + [hiddenTab], left: true) == chat)
        #expect(Panes.spot(in: chat) == CGPoint(x: 650, y: 500))
    }

    @Test func widerCopiesOfAWebPageDoNotHoldThePointer() {
        // The Claude app's window on 2026-11-22, after its side pane was made narrower twice: two
        // hidden browser tabs kept their old widths under the one on show and reached under the
        // chat. pane:left from the web page went to a wider copy, whose middle is in the same
        // web page, every time.
        let sidebar = CGRect(x: 1453, y: 1165, width: 328, height: 1191)
        let chat = CGRect(x: 1792, y: 1106, width: 1034, height: 1307)
        let widest = CGRect(x: 2428, y: 1225, width: 1501, height: 1186)
        let wider = CGRect(x: 2624, y: 1225, width: 1305, height: 1186)
        let web = CGRect(x: 2835, y: 1225, width: 1094, height: 1186)
        let panes = [sidebar, chat, widest, wider, web]
        #expect(Panes.merged(panes) == [sidebar, chat, web])
        #expect(Panes.next(from: Panes.spot(in: web), in: panes, left: true) == chat)
        #expect(Panes.next(from: Panes.spot(in: web), in: panes, left: false) == nil)
        #expect(Panes.next(from: Panes.spot(in: chat), in: panes, left: false) == web)
        // Made wider instead: the tab on show is the wide one. The part both cover is inside it.
        let shown = CGRect(x: 2428, y: 1225, width: 1501, height: 1186)
        let hidden = CGRect(x: 2835, y: 1225, width: 1094, height: 1186)
        let narrowChat = CGRect(x: 1792, y: 1106, width: 628, height: 1307)
        let wide = [sidebar, narrowChat, hidden, shown]
        let landed = Panes.next(from: Panes.spot(in: narrowChat), in: wide, left: false)
        #expect(landed.map { shown.contains(Panes.spot(in: $0)) } == true)
        #expect(Panes.next(from: Panes.spot(in: landed ?? .zero), in: wide, left: true) == narrowChat)
        // Moved and made wider again: a copy that shares no edge with the tab on show, so it is
        // not merged. A move whose landing spot is in the pane the pointer is in is no move.
        let stale = CGRect(x: 2624, y: 1225, width: 1305, height: 1186)
        let onShow = CGRect(x: 2647, y: 1225, width: 1341, height: 1186)
        let chatNow = CGRect(x: 1792, y: 1106, width: 846, height: 1296)
        let now = [sidebar, chatNow, stale, onShow]
        #expect(Panes.merged(now).count == 4)
        #expect(Panes.next(from: Panes.spot(in: onShow), in: now, left: true) == chatNow)
        #expect(Panes.next(from: Panes.spot(in: onShow), in: now, left: false) == nil)
        let under = CGRect(x: 2500, y: 1225, width: 1429, height: 1186)
        #expect(Panes.next(from: Panes.spot(in: onShow), in: [sidebar, chatNow, under, onShow], left: true) == chatNow)
        // Side by side or stacked, panes are not copies.
        #expect(Panes.merged([sidebar, chat]) == [sidebar, chat])
        let top = CGRect(x: 1000, y: 0, width: 400, height: 500)
        let bottom = CGRect(x: 1000, y: 500, width: 400, height: 500)
        #expect(Panes.merged([top, bottom]) == [top, bottom])
    }

    @Test func theChatIsThePaneAboveTheMessageBox() {
        let sidebar = CGRect(x: 0, y: 0, width: 300, height: 1000)
        let chat = CGRect(x: 300, y: 0, width: 700, height: 850)
        let web = CGRect(x: 1000, y: 0, width: 600, height: 1000)
        let box = CGRect(x: 350, y: 870, width: 600, height: 100)
        #expect(Panes.chat(in: [web, sidebar, chat], above: box) == chat)
        // A hidden wider copy of the web page reaching under the box's middle is not the chat.
        let copy = CGRect(x: 500, y: 0, width: 1100, height: 1000)
        #expect(Panes.chat(in: [web, sidebar, chat, copy], above: box) == chat)
        #expect(Panes.chat(in: [web, sidebar], above: box) == nil)
    }

    @Test func paneGoesLeftOrRight() {
        #expect(Action.parse("pane:left") == .pane(left: true))
        #expect(Action.parse("pane: Right") == .pane(left: false))
        #expect(Action.parse("pane:up") == nil && Action.parse("pane") == nil)
        #expect(Action.parse("pane: Chat") == .pointerToChat)
        #expect(Action.pointerToChat.description == "pane:chat")
        #expect(Action.pointerToChat.plainWords == "Move the pointer onto the chat, once the session shows")
        #expect(Action.pointerToChat.typesKeys)
        // An Agent Key's tap shows its session and puts the pointer on its chat, so the stick
        // scrolls the chat at once.
        #expect(Config.builtIn.bindings["AG.press"] == [.ack, .jump, .pointerToChat])
        #expect(Action.pane(left: false).description == "pane:right")
        #expect(Action.pane(left: true).plainWords == "Move the pointer to the pane on the left")
        // It moves the pointer, which macOS gates behind Accessibility like typing.
        #expect(Action.pane(left: true).typesKeys)
    }

    @Test func scrollGoesUpOrDown() throws {
        #expect(Action.parse("scroll:up") == .scroll(up: true))
        #expect(Action.parse("scroll: Down") == .scroll(up: false))
        #expect(Action.parse("scroll:left") == nil && Action.parse("scroll") == nil)
        #expect(Action.scroll(up: false).description == "scroll:down")
        #expect(Action.scroll(up: true).plainWords == "Scroll up")
        // It posts a scroll wheel, which macOS gates behind Accessibility like typing.
        #expect(Action.scroll(up: true).typesKeys)
        let config = try Config.parse(#"{"stick": {"up": "scroll:up", "down": "scroll:down"}}"#)
        #expect(config.actions(for: "STICK", "down", app: "com.apple.Terminal") == [.scroll(up: false)])
        #expect(config.typesKeys)
    }
}

@Suite struct ConfigFileTests {

    @Test func theDefaultFileSurvivesBeingRewritten() throws {
        let file = try #require(ConfigFile(text: Config.defaultFileText))
        #expect(try Config.parse(file.text) == Config.builtIn)
        // Writing what was just written changes nothing.
        #expect(ConfigFile(text: file.text)?.text == file.text)
    }

    @Test func aChangeKeepsTheOrderAndEverythingElse() throws {
        var file = try #require(ConfigFile(text: #"{"keys":{"ACT06":"cmd:FAST","ACT07":"cmd:APPR"},"clickGuard":1}"#))
        file.set(.string("cmd:NEW"), at: ["keys", "ACT06"])
        file.set(.bool(false), at: ["urgentFirst"])
        #expect(file.root.serialized == #"{"keys":{"ACT06":"cmd:NEW","ACT07":"cmd:APPR"},"clickGuard":1,"urgentFirst":false}"#)
        #expect(file.value(at: ["keys", "ACT07"]) == .string("cmd:APPR"))
        #expect(file.value(at: ["keys", "ACT09"]) == nil)
    }

    @Test func aChangeCreatesTheSectionsOnTheWay() throws {
        var file = try #require(ConfigFile(text: "{}"))
        file.set(.string("#112233"), at: ["lighting", "colors", "working"])
        #expect(file.root.serialized == ##"{"lighting":{"colors":{"working":"#112233"}}}"##)
        #expect(try Config.parse(file.text).lighting.colors[.working] == 0x112233)
    }

    @Test func removingAnEntryGivesItsDefaultBack() throws {
        var file = try #require(ConfigFile(text: #"{"keys":{"ACT06":"cmd:NEW"},"batteryWarning":50}"#))
        file.set(nil, at: ["keys", "ACT06"])
        file.set(nil, at: ["batteryWarning"])
        file.set(nil, at: ["stick", "up"])
        #expect(file.root.serialized == #"{"keys":{}}"#)
        let config = try Config.parse(file.text)
        #expect(config.batteryWarning == 20)
        #expect(config.actions(for: "ACT06", "press").map(\.description) == ["text:/fast\\n"])
    }

    @Test func textThatIsNotAnObjectIsNotAConfigFile() {
        #expect(ConfigFile(text: "[1, 2]") == nil)
        #expect(ConfigFile(text: "{ broken") == nil)
    }

    @Test func aRewrittenFileKeepsSectionsOnLinesAndShortEntriesOnOne() throws {
        let file = try #require(ConfigFile(text: #"{"keystrokeApps":[],"keys":{"ACT12":{"press":"key:return","hold":"key:escape"}}}"#))
        #expect(file.text == """
        {
          "keystrokeApps": [],
          "keys": {
            "ACT12": {"press": "key:return", "hold": "key:escape"}
          }
        }

        """)
    }

    @Test func readingKeepsTheOrderOfKeys() throws {
        let value = try #require(JSONValue.parseKeepingOrder(#" { "b" : [1, 2.5, -3e2], "a" : { "z": null, "y": true } } "#))
        #expect(value.serialized == #"{"b":[1,2.5,-300],"a":{"z":null,"y":true}}"#)
    }

    @Test func readingUnderstandsEscapes() throws {
        let value = try #require(JSONValue.parseKeepingOrder(#"["a\"b\\c\n\t\u00e9\ud83d\ude00/\/"]"#))
        #expect(value == .array([.string("a\"b\\c\n\t\u{e9}\u{1F600}//")]))
    }

    @Test func readingAgreesWithTheSortedReader() throws {
        func sorted(_ value: JSONValue) -> JSONValue {
            switch value {
            case let .array(items): .array(items.map(sorted))
            case let .object(pairs): .object(pairs.map { ($0.0, sorted($0.1)) }.sorted { $0.0 < $1.0 })
            default: value
            }
        }
        let kept = try #require(JSONValue.parseKeepingOrder(Config.defaultFileText))
        #expect(sorted(kept) == JSONValue.parse(Config.defaultFileText))
    }

    @Test func readingRefusesWhatIsNotJSON() {
        for text in ["", "{", #"{"a":1,}"#, "[1 2]", #"{"a" 1}"#, "01", "1.", #""\x""#, "tru", #"{"a":1} x"#, "\"a\u{1}b\"", #""\ud83d""#] {
            #expect(JSONValue.parseKeepingOrder(text) == nil, "\(text)")
        }
    }
}

@Suite struct ActionWordsTests {
    @Test func keysReadAsAMacShowsThem() {
        #expect(KeyCombo.symbols("cmd+shift+m") == "⇧⌘M")
        #expect(KeyCombo.symbols("shift+tab") == "⇧ Tab")
        #expect(KeyCombo.symbols("cmd+return") == "⌘ Return")
        #expect(KeyCombo.symbols("down") == "↓")
        #expect(KeyCombo.symbols("ctrl+opt+cmd+]") == "⌃⌥⌘]")
        #expect(KeyCombo.symbols("escape") == "Esc")
    }

    @Test func actionsReadInPlainWords() {
        func words(_ text: String) -> String? { Action.parse(text)?.plainWords }
        #expect(words("key:cmd+b") == "Type ⌘B")
        #expect(words("keydown:f19") == "Hold down F19")
        #expect(words("text:/fast\n") == "Type \"/fast\" and send it")
        #expect(words("text:hello") == "Type \"hello\"")
        #expect(words("click:Suggested next actions/first") == "Press the first button in Suggested next actions")
        #expect(words("click:epitaxy-approval-card/=Next!") == "Press \"Next\" in the prompt card")
        #expect(words("click:*/Allow once") == "Press \"Allow once\" anywhere in the window")
        #expect(words("choose:epitaxy-approval-card/epitaxy-answer-option+Next|Submit/next")
            == "Move to the next answer in the prompt card")
        #expect(words("choose:epitaxy-approval-card/epitaxy-answer-option/mark")
            == "Tick the highlighted answer in the prompt card")
        #expect(words("click:Some other box/Deny") == "Press \"Deny\" in Some other box")
        #expect(words("open:claude://code/new") == "Open claude://code/new")
        #expect(words("forget") == "Forget the session and free the key")
    }

    @Test func everyDefaultActionHasWords() {
        let config = Config.builtIn
        var actions = config.bindings.values.flatMap { $0 }
        for targets in config.commands.values { for triggers in targets.values { actions += triggers.values.flatMap { $0 } } }
        #expect(actions.count > 60)
        for action in actions { #expect(!action.plainWords.isEmpty) }
    }
}
