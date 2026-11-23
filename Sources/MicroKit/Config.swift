import Foundation

/// Everything wrong with a config file, one line per problem.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public var problems: [String]
    public var description: String { problems.joined(separator: "\n") }
}

/// A key press the bridge can type: modifiers plus one key, e.g. `shift+tab`, `cmd+k`, `return`.
public struct KeyCombo: Sendable, Equatable {
    public var code: UInt16
    public var command = false
    public var shift = false
    public var option = false
    public var control = false

    /// Key names to macOS virtual key codes (US layout).
    static let codes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "=": 24, "-": 27, "]": 30, "[": 33, "'": 39, ";": 41, "\\": 42, ",": 43, "/": 44, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]

    public static func parse(_ text: String) -> KeyCombo? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let code = codes[last] else { return nil }
        var combo = KeyCombo(code: code)
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": combo.command = true
            case "shift": combo.shift = true
            case "opt", "option", "alt": combo.option = true
            case "ctrl", "control": combo.control = true
            default: return nil
            }
        }
        return combo
    }
}

public enum KeyPhase: String, Sendable {
    case tap, down, up
}

/// One thing a control can do. Written in the config as a short string:
///
///     none                  nothing
///     ack                   mark this Agent Key's finished session as seen
///     jump                  show this Agent Key's session: its Code session in the Claude app;
///                           elsewhere the same as focus
///     focus                 bring the session's app to the front
///     lock                  turn the pad's lights off, then lock the Mac as ⌃⌘Q does; the keys
///                           show their sessions again once it is unlocked
///     scroll:up             scroll what is under the pointer, as a mouse wheel does. On the
///     scroll:down           stick it scrolls while pushed, faster the farther; on a key, one step
///     pane:left             move the pointer to the next part of the front window that scrolls on
///     pane:right            its own (the chat, a web page, the sidebar), so the stick scrolls it
///     pane:chat             move the pointer onto the chat of the Claude app's window, once the
///                           session `jump` shows is on screen, so the stick scrolls the chat
///     key:shift+tab        type a key combination into the app in front
///     keydown:space         press and keep holding (pair with keyup: on release)
///     keyup:space
///     text:/fast\n          type text into the app in front; \n presses Return
///     sh:git status         run a shell command (MICRO_SESSION, MICRO_CWD, MICRO_PID,
///                           MICRO_STATUS, MICRO_HOST and MICRO_SLOT describe the session)
///     open:https://…        open a URL, file or app
///     click:Box label/first press a button on screen in the app in front: the first, last or Nth
///                           button, or the one with that label, inside the box whose label, id
///                           or one of whose classes is the text before the slash (* means
///                           anywhere). `Box label^2/Dismiss` also tries the two containers
///                           around the box, nearest first. When it presses a button, the rest of
///                           the list is skipped; when there is none, the list carries on
///     choose:Box/opt/next   move the selection among a box's options: the toggles with class `opt`
///                           inside the box. `next` turns on the one after the option that is on,
///                           `prev` the one before; the ends do not wrap. When the box shows
///                           options, the rest of the list is skipped; otherwise it carries on
///     cmd:SPLIT             do what the named command does in the app in front (see `commands`)
public enum Action: Sendable, Equatable, CustomStringConvertible {
    case none
    case ack
    case jump
    case focus
    /// Drop the key's session and free the key.
    case forget
    /// Pins the key's session to its key, or unpins one that is pinned.
    case pin
    /// Lights off, then the Mac locks. macOS refuses writes to the pad once it is locked, so
    /// the bridge turns them off first.
    case lock
    /// Scrolls what is under the pointer, as a mouse wheel does. On the stick it scrolls for as
    /// long as the stick is pushed, faster the farther; on a key, one step.
    case scroll(up: Bool)
    /// Moves the pointer to the next pane that way in the front window: a part that scrolls on
    /// its own, such as the chat, a web page or the sidebar. Scrolling goes where the pointer is.
    case pane(left: Bool)
    /// Moves the pointer onto the chat: the pane above the Claude app's message box. After
    /// `jump`, it waits for the session to show first. It leaves a pointer the user has moved.
    case pointerToChat
    case key(KeyCombo, KeyPhase, spelling: String)
    case text(String)
    case shell(String)
    case open(String)
    case click(ButtonRule)
    case choose(OptionRule)
    /// Types the suggestion the app shows in the named text box, when the box has the focus,
    /// holds nothing typed and shows one. It never settles the press: the next action (Return)
    /// sends the text. With no suggestion it does nothing.
    case complete(String)
    /// A named command; the config says what it does in each app. `trigger` picks which of the
    /// command's triggers to run: its press, unless a whole key was set to the command.
    case command(String, trigger: String = "press")

    public static func parse(_ text: String) -> Action? {
        let head: String
        let rest: String
        if let colon = text.firstIndex(of: ":") {
            head = text[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            rest = String(text[text.index(after: colon)...])
        } else {
            head = text.trimmingCharacters(in: .whitespaces).lowercased()
            rest = ""
        }
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        switch head {
        case "none" where rest.isEmpty: return Action.none
        case "ack" where rest.isEmpty: return .ack
        case "jump" where rest.isEmpty: return .jump
        case "focus" where rest.isEmpty: return .focus
        case "forget" where rest.isEmpty: return .forget
        case "pin" where rest.isEmpty: return .pin
        case "lock" where rest.isEmpty: return .lock
        case "scroll":
            switch trimmed.lowercased() {
            case "up": return .scroll(up: true)
            case "down": return .scroll(up: false)
            default: return nil
            }
        case "pane":
            switch trimmed.lowercased() {
            case "left": return .pane(left: true)
            case "right": return .pane(left: false)
            case "chat": return .pointerToChat
            default: return nil
            }
        case "key", "keydown", "keyup":
            guard let combo = KeyCombo.parse(trimmed) else { return nil }
            let phase: KeyPhase = head == "key" ? .tap : head == "keydown" ? .down : .up
            return .key(combo, phase, spelling: trimmed.lowercased())
        case "text" where !rest.isEmpty: return .text(rest)
        case "sh" where !trimmed.isEmpty: return .shell(trimmed)
        case "open" where !trimmed.isEmpty: return .open(trimmed)
        case "click":
            guard let rule = ButtonRule.parse(trimmed) else { return nil }
            return .click(rule)
        case "choose":
            guard let rule = OptionRule.parse(trimmed) else { return nil }
            return .choose(rule)
        case "complete" where !trimmed.isEmpty: return .complete(trimmed)
        case "cmd" where Action.isCommandName(trimmed): return .command(trimmed.uppercased())
        default: return nil
        }
    }

    /// Command names are short labels such as SPLIT or MIND+.
    static func isCommandName(_ name: String) -> Bool {
        (1 ... 24).contains(name.count) && name.unicodeScalars.allSatisfy { scalar in
            ("a" ... "z").contains(scalar) || ("A" ... "Z").contains(scalar) || ("0" ... "9").contains(scalar)
                || "+-_".unicodeScalars.contains(scalar)
        }
    }

    /// True for actions that type into or click in other apps, which macOS gates behind Accessibility.
    public var typesKeys: Bool {
        switch self {
        case .key, .text, .click, .choose, .complete, .lock, .scroll, .pane, .pointerToChat: true
        default: false
        }
    }

    public var description: String {
        switch self {
        case .none: "none"
        case .ack: "ack"
        case .jump: "jump"
        case .focus: "focus"
        case .forget: "forget"
        case .pin: "pin"
        case .lock: "lock"
        case let .scroll(up): up ? "scroll:up" : "scroll:down"
        case let .pane(left): left ? "pane:left" : "pane:right"
        case .pointerToChat: "pane:chat"
        case let .key(_, phase, spelling): (phase == .tap ? "key:" : phase == .down ? "keydown:" : "keyup:") + spelling
        case let .text(text): "text:" + text.replacingOccurrences(of: "\n", with: "\\n")
        case let .shell(command): "sh:" + command
        case let .open(target): "open:" + target
        case let .click(rule): "click:" + rule.spelling
        case let .choose(rule): "choose:" + rule.spelling
        case let .complete(box): "complete:" + box
        case let .command(name, _): "cmd:" + name
        }
    }
}

/// The user's settings: what every control does and how the lights look.
public struct Config: Sendable, Equatable {
    public struct Lighting: Sendable, Equatable {
        /// 0…1.
        public var brightness = 1.0
        /// Seconds without activity before the lights turn off. 0 keeps them on.
        public var autoDimSeconds = 0
        /// Pulse the Agent Key of the session the Claude app shows.
        public var pulseSelected = true
        /// Catch ⌃⌘Q, turn the lights off, then let the lock through. Any other lock leaves
        /// them as they were: macOS refuses writes to the pad once the Mac is locked.
        public var offWhenLocked = false
        public var colors: [AgentStatus: UInt32] = [:]

        public func color(_ status: AgentStatus) -> UInt32 { colors[status] ?? status.color }
    }

    public var lighting = Lighting()
    /// Bundle ids that may receive typed keys. Empty: whichever app is in front.
    public var keystrokeApps: [String] = []
    /// Bundle ids the bridge leaves the pad to while one of them is in front: no lights, no key
    /// actions. See `PadSharing`.
    public var stepAsideFor: [String] = []
    /// Layers whose visit passes the pad to another app, by number (2 to 9; layer 1 has the
    /// keys). A visit gives that app the pad and the next one takes it back, and the app in
    /// front no longer matters for it. See `PadSharing`.
    public var layers: [Int: String] = [:]
    /// The pad has its own keys on the layers in `layers` as well, put there with Work Louder
    /// Input. Then one tap is enough: the layer the pad is on says who has it.
    public var layerKeys = false
    /// Show a notification when the pad is on a layer where its keys do not reach us.
    public var layerWarning = true
    /// Show a notification when the pad's battery falls to this percent while it is not charging.
    /// Zero turns this off.
    public var batteryWarning = 20
    /// Seconds a key stays quiet after its `click:` pressed a button. Zero turns this off.
    public var clickGuard = 1.0
    /// When all six Agent Keys are taken, a session without one takes the key of a session
    /// that wants its person less.
    public var urgentFirst = true
    /// Hours a Claude app session that ended keeps its Agent Key, so a press opens it again.
    /// Infinity: until another session takes the key. Zero: the key goes dark as soon as the
    /// session ends.
    public var rememberHours = Double.infinity
    /// Actions by "<control>.<trigger>", e.g. "ACT07.press", "AG.doubleTap", "STICK.up", "DIAL.cw".
    public var bindings: [String: [Action]] = [:]

    /// App groups: a short name for a set of bundle ids, such as "claude" or "terminal".
    public var apps: [String: [String]] = [:]
    /// Named commands: name → target (an app group, a bundle id or "default") → trigger → actions.
    public var commands: [String: [String: [String: [Action]]]] = [:]

    public static let triggers = ["press", "release", "doubleTap", "hold"]
    public static let keyControls = ["ACT06", "ACT07", "ACT08", "ACT09", "ACT10", "ACT11", "WIDE", "ACT12"]
    public static let stickDirections = ["up", "right", "down", "left"]

    /// What `control` does on `trigger` while `app` (a bundle id) is in front. A `cmd:NAME`
    /// entry becomes what that command does in that app.
    public func actions(for control: String, _ trigger: String, app: String? = nil) -> [Action] {
        (bindings["\(control).\(trigger)"] ?? []).flatMap { action -> [Action] in
            guard case let .command(name, part) = action else { return [action] }
            return command(name, app: app)?[part] ?? []
        }
    }

    /// A command's triggers for one app: its group's entry, then its bundle id's, then "default".
    public func command(_ name: String, app: String?) -> [String: [Action]]? {
        guard let targets = commands[name] else { return nil }
        if let app {
            for group in apps.keys.sorted() where apps[group]?.contains(app) == true {
                if let found = targets[group] { return found }
            }
            if let found = targets[app] { return found }
        }
        return targets["default"]
    }

    public func hasDoubleTap(_ control: String, app: String? = nil) -> Bool {
        !actions(for: control, "doubleTap", app: app).isEmpty
    }

    public var typesKeys: Bool {
        bindings.values.contains { $0.contains(where: \.typesKeys) }
            || commands.values.contains { $0.values.contains { $0.values.contains { $0.contains(where: \.typesKeys) } } }
    }

    /// The file written by `micro config init`, and the defaults behind every missing entry.
    public static let defaultFileText = #"""
    {
      "lighting": {
        "brightness": 100,
        "autoDimSeconds": 0,
        "pulseSelected": true,
        "offWhenLocked": false,
        "colors": {
          "working": "#304FFE",
          "needs-you": "#FF6D00",
          "idle": "#FFFFFF",
          "done": "#00FF4C",
          "failed": "#FF0033"
        }
      },
      "keystrokeApps": [],
      "stepAsideFor": ["com.openai.codex"],
      "layers": {},
      "layerKeys": false,
      "layerWarning": true,
      "batteryWarning": 20,
      "clickGuard": 1,
      "urgentFirst": true,
      "rememberHours": "always",
      "apps": {
        "claude": ["com.anthropic.claudefordesktop"],
        "terminal": ["com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2"]
      },
      "agentKeys": {
        "press": ["ack", "jump", "pane:chat"],
        "hold": "forget"
      },
      "keys": {
        "ACT06": "cmd:FAST",
        "ACT07": "cmd:APPR",
        "ACT08": "cmd:REJ",
        "ACT09": "cmd:SPLIT",
        "WIDE": "cmd:MIC",
        "ACT12": "cmd:CODEX"
      },
      "stick": {
        "up": "cmd:PLAN",
        "right": "cmd:FORWARD",
        "down": "cmd:SIDEBAR",
        "left": "cmd:BACK"
      },
      "dial": {
        "cw": "cmd:PREV",
        "ccw": "cmd:NEXT",
        "press": "cmd:PICK",
        "hold": "cmd:PADSETTINGS"
      },
      "commands": {
        "FAST": {"default": "text:/fast\n"},
        "NEXT": {"claude": ["choose:epitaxy-approval-card/epitaxy-answer-option+Next|Submit/next", "key:down"], "default": "key:down"},
        "PREV": {"claude": ["choose:epitaxy-approval-card/epitaxy-answer-option+Next|Submit/prev", "key:up"], "default": "key:up"},
        "PICK": {"claude": ["choose:epitaxy-approval-card/epitaxy-answer-option/mark", "click:epitaxy-approval-card/=Next!", "click:epitaxy-approval-card/=Submit!", "key:return"], "default": "key:return"},
        "APPR": {"claude": ["click:Suggested next actions/first", "click:epitaxy-approval-card/Allow once", "click:epitaxy-approval-card/=Next!", "click:epitaxy-approval-card/=Submit!", "key:cmd+return"], "default": "key:return"},
        "REJ": {"claude": ["click:Suggested next actions/2", "click:Suggested next actions^2/Dismiss", "click:epitaxy-approval-card/Deny", "click:epitaxy-approval-card/=Skip!", "key:escape"], "default": "key:escape"},
        "SPLIT": {"claude": "key:cmd+opt+o", "terminal": "text:/branch\n"},
        "MIC": {
          "claude": {"press": "key:cmd+d", "release": "key:cmd+d"},
          "terminal": {"press": "keydown:space", "release": "keyup:space"}
        },
        "MIC1": {
          "claude": {"press": "key:cmd+d", "release": "key:cmd+d"},
          "terminal": {"press": "keydown:space", "release": "keyup:space"}
        },
        "CODEX": {"claude": ["complete:Prompt", "key:return"], "default": "key:return"},
        "NEW": {"claude": "key:cmd+n", "terminal": "text:/clear\n"},
        "NAV": {"claude": "key:cmd+ctrl+\\"},
        "TERM": {"claude": "key:cmd+j"},
        "DIFF": {"claude": "key:cmd+shift+d", "terminal": "text:/diff\n"},
        "DEL": {"claude": "key:cmd+opt+a"},
        "MAGIC": {"claude": "key:cmd+opt+p"},
        "PARTY": {"claude": "key:cmd+;", "terminal": "text:/btw "},
        "MIND+": {"claude": "key:cmd+shift+e", "terminal": "text:/effort\n"},
        "MIND-": {"claude": "key:cmd+shift+e", "terminal": "text:/effort\n"},
        "UPL": {"claude": "key:cmd+u"},
        "PAINT": {"claude": "key:cmd+u"},
        "FOLD": {"claude": "key:cmd+shift+o"},
        "LAB": {"claude": "key:cmd+,", "terminal": "text:/config\n"},
        "SETUP": {"claude": "key:cmd+,", "terminal": "text:/config\n"},
        "APPS": {"claude": "text:/", "terminal": "text:/skills\n"},
        "TIME": {"terminal": "text:/schedule\n"},
        "DWN": {"terminal": "text:/export\n"},
        "BUG": {"default": "text:/feedback\n"},
        "OAI": {"default": "open:https://code.claude.com/docs"},
        "GIT": {"default": "text:Commit the current changes."},
        "BRANCH": {"default": "text:Create a new branch for this work."},
        "PR": {"default": "text:Open a pull request for this branch."},
        "BRCH": {"default": "text:Open a draft pull request for this branch."},
        "MRG": {"default": "text:Merge the pull request."},
        "YOLO": {"default": "text::yolo:"},
        "YEET": {"default": "text::yeet:"},
        "PLAY": {},
        "EMPT1": {},
        "EMPT2": {},
        "EMPT3": {},
        "EMPT4": {},
        "EMPT5": {},
        "COMPUTER": {"default": "text:Use computer use to "},
        "PLAN": {"claude": "key:cmd+shift+m", "terminal": "key:shift+tab"},
        "FORWARD": {"claude": "key:cmd+shift+]"},
        "BACK": {"claude": "key:cmd+shift+["},
        "SIDEBAR": {"claude": "key:cmd+b"},
        "LOCK": {"default": "lock"},
        "PADSETTINGS": {"default": "sh:open -t \"$HOME/Library/Application Support/micro-bridge/config.json\""}
      }
    }

    """#

    public static let builtIn: Config = {
        do {
            return try parse(defaultFileText, base: Config())
        } catch {
            fatalError("built-in config is invalid: \(error)")
        }
    }()

    /// Reads a config file. A missing file gives the built-in defaults.
    public static func load(_ path: String) throws(ConfigError) -> Config {
        guard FileManager.default.fileExists(atPath: path) else { return builtIn }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ConfigError(problems: ["cannot read \(path)"])
        }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    /// Parses config JSON. Whatever the file leaves out keeps its built-in default; a control
    /// the file does mention does exactly what the file says and nothing else.
    public static func parse(_ text: String) throws(ConfigError) -> Config {
        try parse(text, base: builtIn)
    }

    static func parse(_ text: String, base: Config) throws(ConfigError) -> Config {
        guard let root = JSONValue.parse(text), case let .object(sections) = root else {
            throw ConfigError(problems: ["the file is not a JSON object"])
        }
        var config = base
        var reader = Reader()
        for (name, value) in sections {
            switch name {
            case "lighting": reader.lighting(value, into: &config.lighting)
            case "keystrokeApps":
                guard case let .array(items) = value, items.allSatisfy({ $0.string != nil }) else {
                    reader.problems.append("keystrokeApps: expected a list of app bundle ids")
                    continue
                }
                config.keystrokeApps = items.compactMap(\.string)
            case "stepAsideFor":
                guard case let .array(items) = value, items.allSatisfy({ $0.string != nil }) else {
                    reader.problems.append("stepAsideFor: expected a list of app bundle ids")
                    continue
                }
                config.stepAsideFor = items.compactMap(\.string)
            case "layers":
                guard case let .object(pairs) = value else {
                    reader.problems.append(#"layers: expected an object such as {"2": "com.openai.codex"}"#)
                    continue
                }
                var layers: [Int: String] = [:]
                for (key, app) in pairs {
                    guard let number = Int(key), (2 ... 9).contains(number) else {
                        reader.problems.append("layers: \(key): expected a layer from 2 to 9 (layer 1 is the bridge's)")
                        continue
                    }
                    guard let id = app.string, !id.isEmpty else {
                        reader.problems.append("layers.\(key): expected an app's bundle id")
                        continue
                    }
                    layers[number] = id
                }
                config.layers = layers
            case "layerKeys":
                guard let flag = value.bool else {
                    reader.problems.append("layerKeys: expected true or false")
                    continue
                }
                config.layerKeys = flag
            case "layerWarning":
                guard let flag = value.bool else {
                    reader.problems.append("layerWarning: expected true or false")
                    continue
                }
                config.layerWarning = flag
            case "batteryWarning":
                guard let percent = value.int, (0 ... 100).contains(percent) else {
                    reader.problems.append("batteryWarning: expected a percent from 0 to 100 (0 turns it off)")
                    continue
                }
                config.batteryWarning = percent
            case "clickGuard":
                guard let seconds = value.double, (0 ... 10).contains(seconds) else {
                    reader.problems.append("clickGuard: expected seconds from 0 to 10 (0 turns it off)")
                    continue
                }
                config.clickGuard = seconds
            case "urgentFirst", "needsYouFirst":
                // "needsYouFirst" is the older name of the same switch.
                guard let flag = value.bool else {
                    reader.problems.append("\(name): expected true or false")
                    continue
                }
                config.urgentFirst = flag
            case "rememberHours":
                if value.string == "always" {
                    config.rememberHours = .infinity
                } else if let hours = value.double, (0 ... 8760).contains(hours) {
                    config.rememberHours = hours
                } else {
                    reader.problems.append("rememberHours: expected \"always\", or hours from 0 to 8760 (0 turns it off)")
                }
            case "apps":
                guard case let .object(groups) = value else {
                    reader.problems.append("apps: expected an object of group name to a list of bundle ids")
                    continue
                }
                for (group, list) in groups {
                    guard case let .array(items) = list, items.allSatisfy({ $0.string != nil }) else {
                        reader.problems.append("apps.\(group): expected a list of app bundle ids")
                        continue
                    }
                    config.apps[group] = items.compactMap(\.string)
                }
            case "commands":
                guard case let .object(entries) = value else {
                    reader.problems.append("commands: expected an object of command name to what it does")
                    continue
                }
                for (name, entry) in entries {
                    guard Action.isCommandName(name) else {
                        reader.problems.append("commands.\(name): a name is 1 to 24 letters, digits, + - or _")
                        continue
                    }
                    if let targets = reader.command(entry, at: "commands.\(name)") {
                        config.commands[name.uppercased()] = targets
                    }
                }
            case "agentKeys":
                reader.control(value, name: "AG", at: "agentKeys", allowed: triggers + ["empty"], bare: "press",
                               into: &config.bindings)
            case "keys":
                guard case let .object(keys) = value else {
                    reader.problems.append("keys: expected an object")
                    continue
                }
                for (key, binding) in keys {
                    guard keyControls.contains(key) else {
                        reader.problems.append("keys.\(key): unknown key; use \(keyControls.joined(separator: ", "))")
                        continue
                    }
                    reader.control(binding, name: key, at: "keys.\(key)", allowed: triggers, bare: "press", into: &config.bindings)
                }
            case "stick":
                reader.control(value, name: "STICK", at: "stick", allowed: stickDirections, bare: nil, into: &config.bindings)
            case "dial":
                reader.control(value, name: "DIAL", at: "dial", allowed: ["cw", "ccw"] + triggers, bare: nil, into: &config.bindings)
            default:
                reader.problems.append(
                    "\(name): unknown section; use lighting, keystrokeApps, stepAsideFor, layers, layerKeys, layerWarning, batteryWarning, clickGuard, urgentFirst, rememberHours, apps, agentKeys, keys, stick, dial, commands")
            }
        }
        // Names can only be checked once every section is in.
        for (name, targets) in config.commands.sorted(by: { $0.key < $1.key }) {
            for target in targets.keys.sorted()
                where target != "default" && config.apps[target] == nil && !target.contains(".") {
                reader.problems.append(
                    "commands.\(name).\(target): no app group with that name; add it under apps, or use a bundle id or default")
            }
        }
        for (binding, actions) in config.bindings.sorted(by: { $0.key < $1.key }) {
            for case let .command(name, _) in actions where config.commands[name] == nil {
                reader.problems.append("\(binding): there is no command named \(name)")
            }
        }
        if !reader.problems.isEmpty { throw ConfigError(problems: reader.problems) }
        return config
    }

    private struct Reader {
        var problems: [String] = []

        mutating func actions(_ value: JSONValue, at path: String) -> [Action]? {
            let texts: [JSONValue]
            switch value {
            case .string: texts = [value]
            case let .array(items): texts = items
            default:
                problems.append("\(path): expected an action such as \"key:return\", or a list of them")
                return nil
            }
            var out: [Action] = []
            var ok = true
            for item in texts {
                guard let text = item.string, let action = Action.parse(text) else {
                    problems.append("\(path): \(item.serialized) is not an action")
                    ok = false
                    continue
                }
                if action != .none { out.append(action) }
            }
            return ok ? out : nil
        }

        /// One command: an action, a list or an object of triggers (the same in every app), or an
        /// object of app group, bundle id or "default" to any of those.
        mutating func command(_ value: JSONValue, at path: String) -> [String: [String: [Action]]]? {
            guard case let .object(pairs) = value,
                  pairs.isEmpty || !pairs.allSatisfy({ Config.triggers.contains($0.0) }) else {
                return triggers(value, at: path).map { ["default": $0] }
            }
            var targets: [String: [String: [Action]]] = [:]
            var ok = true
            for (target, binding) in pairs {
                if let found = triggers(binding, at: "\(path).\(target)") { targets[target] = found } else { ok = false }
            }
            return ok ? targets : nil
        }

        private mutating func triggers(_ value: JSONValue, at path: String) -> [String: [Action]]? {
            var out: [String: [Action]] = [:]
            var ok = true
            if case let .object(pairs) = value {
                for (key, binding) in pairs {
                    guard Config.triggers.contains(key) else {
                        problems.append("\(path).\(key): unknown entry; use \(Config.triggers.joined(separator: ", "))")
                        ok = false
                        continue
                    }
                    if let list = actions(binding, at: "\(path).\(key)") { out[key] = list } else { ok = false }
                }
            } else if let list = actions(value, at: path) {
                out["press"] = list
            } else {
                ok = false
            }
            for (key, list) in out where list.contains(where: { if case .command = $0 { true } else { false } }) {
                problems.append("\(path).\(key): a command cannot use cmd:")
                ok = false
            }
            return ok ? out : nil
        }

        /// Replaces everything `name` does with what `value` says.
        mutating func control(_ value: JSONValue, name: String, at path: String, allowed: [String],
                              bare: String?, into bindings: inout [String: [Action]]) {
            for key in bindings.keys where key.hasPrefix(name + ".") { bindings[key] = nil }
            if case let .object(pairs) = value {
                for (key, binding) in pairs {
                    guard allowed.contains(key) else {
                        problems.append("\(path).\(key): unknown entry; use \(allowed.joined(separator: ", "))")
                        continue
                    }
                    if let list = actions(binding, at: "\(path).\(key)"), !list.isEmpty {
                        bindings["\(name).\(key)"] = list
                    }
                }
            } else if let bare {
                guard let list = actions(value, at: path), !list.isEmpty else { return }
                if list.count == 1, case let .command(command, _) = list[0] {
                    // A key that is a command takes every trigger the command has.
                    for trigger in Config.triggers {
                        bindings["\(name).\(trigger)"] = [.command(command, trigger: trigger)]
                    }
                } else {
                    bindings["\(name).\(bare)"] = list
                }
            } else {
                problems.append("\(path): expected an object with \(allowed.joined(separator: ", "))")
            }
        }

        mutating func lighting(_ value: JSONValue, into lighting: inout Lighting) {
            guard case let .object(pairs) = value else {
                problems.append("lighting: expected an object")
                return
            }
            for (key, setting) in pairs {
                switch key {
                case "brightness":
                    guard let percent = setting.double, (0 ... 100).contains(percent) else {
                        problems.append("lighting.brightness: expected a number from 0 to 100")
                        continue
                    }
                    lighting.brightness = percent / 100
                case "autoDimSeconds":
                    guard let seconds = setting.int, seconds >= 0 else {
                        problems.append("lighting.autoDimSeconds: expected a whole number of seconds, 0 for never")
                        continue
                    }
                    lighting.autoDimSeconds = seconds
                case "pulseSelected":
                    guard let flag = setting.bool else {
                        problems.append("lighting.pulseSelected: expected true or false")
                        continue
                    }
                    lighting.pulseSelected = flag
                case "offWhenLocked":
                    guard let flag = setting.bool else {
                        problems.append("lighting.offWhenLocked: expected true or false")
                        continue
                    }
                    lighting.offWhenLocked = flag
                case "colors":
                    guard case let .object(colors) = setting else {
                        problems.append("lighting.colors: expected an object")
                        continue
                    }
                    for (name, color) in colors {
                        guard let status = AgentStatus(rawValue: name), status != .off else {
                            problems.append("lighting.colors.\(name): unknown status; use working, needs-you, idle, done, failed")
                            continue
                        }
                        guard let text = color.string, text.count == 7, text.hasPrefix("#"),
                              let rgb = UInt32(text.dropFirst(), radix: 16) else {
                            problems.append("lighting.colors.\(name): expected a color like \"#304FFE\"")
                            continue
                        }
                        lighting.colors[status] = rgb
                    }
                default:
                    problems.append("lighting.\(key): unknown setting; use brightness, autoDimSeconds, pulseSelected, offWhenLocked, colors")
                }
            }
        }
    }
}
