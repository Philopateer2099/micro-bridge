import Foundation
import MicroKit

/// The kinds of action the window can make. The raw value is the word the file starts one with.
enum ActionKind: String, CaseIterable, Identifiable, Sendable {
    case command = "cmd"
    case key
    case text
    case keyDown = "keydown"
    case keyUp = "keyup"
    case click
    case choose
    case scroll
    case pane
    case shell = "sh"
    case open
    case ack
    case jump
    case focus
    case forget
    case pin
    case lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "Run a command"
        case .key: "Type a key"
        case .text: "Type text"
        case .keyDown: "Hold a key down"
        case .keyUp: "Let a key go"
        case .click: "Press a button on screen"
        case .choose: "Move among answers"
        case .scroll: "Scroll up or down"
        case .pane: "Move the pointer to another pane"
        case .shell: "Run a shell command"
        case .open: "Open a link, file or app"
        case .ack: "Mark the session as read"
        case .jump: "Show the session"
        case .focus: "Bring the session's app forward"
        case .forget: "Forget the session"
        case .pin: "Pin or unpin the session"
        case .lock: "Turn the lights off and lock the Mac"
        }
    }

    /// False for the kinds that are one word in the file.
    var takesValue: Bool {
        switch self {
        case .ack, .jump, .focus, .forget, .pin, .lock: false
        default: true
        }
    }

    var isKey: Bool { self == .key || self == .keyDown || self == .keyUp }

    /// What it takes is long: a sentence, a rule, a shell command or an address.
    var isLong: Bool {
        switch self {
        case .text, .click, .choose, .shell, .open: true
        default: false
        }
    }

    /// What an empty field shows.
    var placeholder: String {
        switch self {
        case .key: "cmd+shift+m"
        case .keyDown, .keyUp: "space"
        case .text: "/fast"
        case .click: "box/button"
        case .choose: "box/class/next"
        case .scroll: "up"
        case .pane: "left"
        case .shell: "say done"
        case .open: "https://example.com"
        default: ""
        }
    }

    /// What to write, for a value the bridge does not take.
    var advice: String {
        switch self {
        case .command: "Pick a command."
        case .key, .keyDown, .keyUp: "Write one key with its modifiers, such as cmd+shift+m, return or f5."
        case .text: "Write the text to type."
        case .click: "Write the box, a slash, then the button, such as epitaxy-approval-card/Allow once."
        case .choose: "Write the box, the options' class, then next, prev or mark, such as card/option/next."
        case .scroll: "Write up or down."
        case .pane: "Write left, right or chat."
        case .shell: "Write the command to run."
        case .open: "Write a link, or the path of a file or an app."
        default: ""
        }
    }

    /// The kinds a menu offers, in groups. A command cannot run another command.
    static func groups(inCommand: Bool) -> [[ActionKind]] {
        let all: [[ActionKind]] = [
            inCommand ? [] : [.command],
            [.key, .text, .keyDown, .keyUp],
            [.click, .choose, .scroll, .pane],
            [.shell, .open],
            [.ack, .jump, .focus, .forget, .pin],
            [.lock],
        ]
        return all.filter { !$0.isEmpty }
    }
}

/// One action while the window edits it.
struct ActionDraft: Equatable, Sendable {
    var kind: ActionKind
    /// What follows the colon in the file. For text, without the Return at its end.
    var value = ""
    /// Text only: press Return after typing it.
    var sends = false

    init(kind: ActionKind, value: String = "", sends: Bool = false) {
        self.kind = kind
        self.value = value
        self.sends = sends
    }

    /// Nil for `none` and for text the bridge does not read as an action.
    init?(spelling: String) {
        guard Action.parse(spelling) != nil else { return nil }
        let head: String
        let rest: String
        if let colon = spelling.firstIndex(of: ":") {
            head = String(spelling[..<colon])
            rest = String(spelling[spelling.index(after: colon)...])
        } else {
            head = spelling
            rest = ""
        }
        guard let kind = ActionKind(rawValue: head.trimmingCharacters(in: .whitespaces).lowercased()) else { return nil }
        self.kind = kind
        switch kind {
        case .text:
            sends = rest.hasSuffix("\n")
            value = sends ? String(rest.dropLast()) : rest
        case .command:
            value = rest.trimmingCharacters(in: .whitespaces).uppercased()
        default:
            value = rest.trimmingCharacters(in: .whitespaces)
        }
    }

    /// The action as the file writes it.
    var spelling: String {
        switch kind {
        case .text: "text:" + value + (sends ? "\n" : "")
        case .command: "cmd:" + value.trimmingCharacters(in: .whitespaces).uppercased()
        case _ where !kind.takesValue: kind.rawValue
        default: kind.rawValue + ":" + value.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Why the bridge would not take it, or nil when it would.
    func problem(inCommand: Bool) -> String? {
        if kind == .command, inCommand { return "A command cannot run another command." }
        return Action.parse(spelling) == nil ? kind.advice : nil
    }
}

/// One list of actions in the file: what a control does on one trigger, or what a command does
/// on one trigger in one app.
struct ActionList: Hashable, Sendable {
    enum Owner: Hashable, Sendable {
        /// One of the lower keys, by its name in the file.
        case key(String)
        /// agentKeys, dial or stick.
        case section(String)
        /// A command in one target: an app group, a bundle id or "default".
        case command(String, target: String)

        var id: String {
            switch self {
            case let .key(name): "keys/" + name
            case let .section(name): name
            case let .command(name, target): "commands/\(name)/\(target)"
            }
        }

        var inCommand: Bool {
            if case .command = self { true } else { false }
        }
    }

    var owner: Owner
    var trigger: String

    var id: String { owner.id + "/" + trigger }
}

extension BridgeModel {
    // MARK: Lists of actions

    /// The actions in a binding as the file writes it: one action or a list. `none` is left out.
    static func spellings(_ value: JSONValue?) -> [String] { ConfigFile.spellings(value) }

    /// One action is written as a string, several as a list.
    static func binding(_ actions: [String]) -> JSONValue { ConfigFile.binding(actions) }

    /// A control or a command target as one list per trigger. An action or a list on its own
    /// is the press.
    static func triggerLists(_ value: JSONValue?) -> [(trigger: String, actions: [String])] { ConfigFile.triggerLists(value) }

    func lists(of owner: ActionList.Owner) -> [(trigger: String, actions: [String])] {
        switch owner {
        case let .key(name): Self.triggerLists(value(at: ["keys", name]).value)
        case let .section(name): triggers(of: name).map { ($0.0, Self.spellings($0.1)) }
        case let .command(name, target): Self.triggerLists(commandEntry(name).first { $0.0 == target }?.1)
        }
    }

    func actions(in list: ActionList) -> [String] {
        lists(of: list.owner).first { $0.trigger == list.trigger }?.actions ?? []
    }

    /// Replaces one list. The owner's other triggers are written back as they are, because a
    /// control or a command the file mentions does only what the file says. False when the
    /// bridge would refuse the change; `notice` then says why.
    @discardableResult
    func setActions(_ actions: [String], in list: ActionList) -> Bool {
        let kept = actions.filter { Action.parse($0) != Action.none }
        var lists = lists(of: list.owner).filter { !$0.actions.isEmpty }
        if let index = lists.firstIndex(where: { $0.trigger == list.trigger }) {
            if kept.isEmpty { lists.remove(at: index) } else { lists[index].actions = kept }
        } else if !kept.isEmpty {
            lists.append((list.trigger, kept))
        }
        let object = JSONValue.object(lists.map { ($0.trigger, Self.binding($0.actions)) })
        switch list.owner {
        case let .key(name):
            // Always an object: a key written as one command on its own takes every trigger
            // of that command, which is another thing.
            set(object, at: ["keys", name])
        case let .section(name):
            set(object, at: [name])
        case let .command(name, target):
            // The same rule the bridge uses for the panel in Orca.
            let defaults = defaults
            edit { $0.setCommand(name, target: target, trigger: list.trigger, actions: kept, defaults: defaults) }
        }
        return self.actions(in: list) == kept
    }

    /// Turns a key that is one command, or nothing, into a key with its own list per trigger.
    /// Its press starts as what the key was.
    func giveKeyOwnActions(_ key: String) {
        let lists = Self.triggerLists(value(at: ["keys", key]).value).filter { !$0.actions.isEmpty }
        set(.object(lists.map { ($0.trigger, Self.binding($0.actions)) }), at: ["keys", key])
    }

    // MARK: Commands

    /// The name the file itself has for a command. The bridge reads names in any case.
    private func commandKey(_ name: String) -> String {
        file?.commandKey(name) ?? name
    }

    /// A command as targets, whichever of its forms the file uses: an action, a list or an
    /// object of triggers is what it does everywhere.
    private func commandEntry(_ name: String) -> [(String, JSONValue)] {
        (file ?? defaults)?.commandEntry(name, defaults: defaults) ?? []
    }

    /// Every command: the ones on the pad, then the ones a person made, then the rest.
    var allCommands: [String] {
        let onPad = Set(config.commands.keys.filter { !uses(of: $0).isEmpty })
        func rank(_ name: String) -> Int { onPad.contains(name) ? 0 : commandIsBuiltIn(name) ? 2 : 1 }
        return config.commands.keys.sorted { first, second in
            if rank(first) != rank(second) { return rank(first) < rank(second) }
            return title(first).localizedCaseInsensitiveCompare(title(second)) == .orderedAscending
        }
    }

    /// The command does something in some app.
    func commandDoesSomething(_ name: String) -> Bool {
        config.commands[name]?.values.contains { $0.values.contains { !$0.isEmpty } } ?? false
    }

    /// One of the commands the bridge comes with.
    func commandIsBuiltIn(_ name: String) -> Bool {
        defaults?.value(at: ["commands", name]) != nil
    }

    /// The file leaves the command out, or says what the bridge says anyway.
    func commandIsDefault(_ name: String) -> Bool {
        value(at: ["commands", commandKey(name)]).isDefault
    }

    /// Where a command can do something: the app groups, any app the file names for it, and
    /// "default" for every other app.
    func commandTargets(_ name: String) -> [String] {
        func rank(_ group: String) -> Int { ["claude", "terminal", "orca"].firstIndex(of: group) ?? 3 }
        var targets = config.apps.keys.sorted { (rank($0), $0) < (rank($1), $1) }
        for (target, _) in commandEntry(name) where target != "default" && !targets.contains(target) {
            targets.append(target)
        }
        return targets + ["default"]
    }

    func targetTitle(_ target: String) -> String {
        switch target {
        case "claude": "In the Claude app"
        case "terminal": "In a terminal"
        case "orca": "In Orca"
        case "default": "Everywhere else"
        default: config.apps[target] == nil ? "In " + target : "In the \(target) apps"
        }
    }

    /// The controls that run a command, as the window names them.
    func uses(of command: String) -> [String] {
        let controls = Set(config.bindings.compactMap { key, actions -> String? in
            let runs = actions.contains { action in
                if case let .command(name, _) = action { return name == command }
                return false
            }
            return runs ? key.split(separator: ".").first.map(String.init) : nil
        })
        return (["AG"] + Config.keyControls + ["DIAL", "STICK"]).filter(controls.contains).map { control in
            switch control {
            case "AG": "Agent Keys"
            case "DIAL": "Dial"
            case "STICK": "Stick"
            default: PadControl.keyTitles[control] ?? control
            }
        }
    }

    /// Makes a command that does nothing yet. Returns why it could not, or nil.
    func addCommand(_ name: String) -> String? {
        guard case let .command(made, _)? = Action.parse("cmd:" + name.trimmingCharacters(in: .whitespaces)) else {
            return "A name is 1 to 24 letters, digits, + - or _."
        }
        guard config.commands[made] == nil else { return "There is already a command called \(made)." }
        set(.object([]), at: ["commands", made])
        return config.commands[made] == nil ? notice ?? "The command was not saved." : nil
    }

    /// Takes a command out of the file. One the bridge comes with is then as the bridge has it.
    func removeCommand(_ name: String) {
        set(nil, at: ["commands", commandKey(name)])
    }
}
