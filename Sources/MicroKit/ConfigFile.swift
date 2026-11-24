import Foundation

/// The config file as JSON that can be changed in place. Keys stay in the order the file has
/// them, and whatever a change does not touch is written back as it was read.
public struct ConfigFile: Sendable, Equatable {
    public private(set) var root: JSONValue

    /// Nil when `text` is not a JSON object.
    public init?(text: String) {
        guard let value = JSONValue.parseKeepingOrder(text), case .object = value else { return nil }
        root = value
    }

    public func value(at path: [String]) -> JSONValue? {
        var node = root
        for key in path {
            guard let next = node[key] else { return nil }
            node = next
        }
        return node
    }

    /// Sets the value at `path` and creates the objects on the way there. Nil removes the entry.
    public mutating func set(_ value: JSONValue?, at path: [String]) {
        guard !path.isEmpty else { return }
        root = Self.setting(value, at: path[...], in: root)
    }

    private static func setting(_ value: JSONValue?, at path: ArraySlice<String>, in node: JSONValue) -> JSONValue {
        guard let key = path.first else { return value ?? .null }
        var pairs: [(String, JSONValue)] = []
        if case let .object(existing) = node { pairs = existing }
        let rest = path.dropFirst()
        let index = pairs.firstIndex { $0.0 == key }
        if rest.isEmpty {
            if let value {
                if let index { pairs[index].1 = value } else { pairs.append((key, value)) }
            } else if let index {
                pairs.remove(at: index)
            }
        } else if let index {
            pairs[index].1 = setting(value, at: rest, in: pairs[index].1)
        } else if value != nil {
            pairs.append((key, setting(value, at: rest, in: .object([]))))
        }
        return .object(pairs)
    }

    /// The file's text, indented by two spaces. The file and each of its sections are spread
    /// over lines; below that, a list or an object that fits on one line stays on one.
    public var text: String {
        var out = ""
        Self.write(root, depth: 0, into: &out)
        return out + "\n"
    }

    private static let width = 110

    private static func write(_ value: JSONValue, depth: Int, into out: inout String) {
        let indent = String(repeating: "  ", count: depth)
        switch value {
        case let .object(pairs) where !pairs.isEmpty && (depth < 2 || indent.count + inline(value).count > width):
            out += "{\n"
            for (index, pair) in pairs.enumerated() {
                out += indent + "  " + JSONValue.string(pair.0).serialized + ": "
                write(pair.1, depth: depth + 1, into: &out)
                out += index == pairs.count - 1 ? "\n" : ",\n"
            }
            out += indent + "}"
        case let .array(items) where !items.isEmpty && indent.count + inline(value).count > width:
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += indent + "  "
                write(item, depth: depth + 1, into: &out)
                out += index == items.count - 1 ? "\n" : ",\n"
            }
            out += indent + "]"
        default:
            out += inline(value)
        }
    }

    private static func inline(_ value: JSONValue) -> String {
        switch value {
        case let .array(items):
            "[" + items.map(inline).joined(separator: ", ") + "]"
        case let .object(pairs):
            pairs.isEmpty
                ? "{}"
                : "{" + pairs.map { JSONValue.string($0.0).serialized + ": " + inline($0.1) }.joined(separator: ", ") + "}"
        default:
            value.serialized
        }
    }
}

// MARK: Commands

extension Config {
    /// Names people have for the commands the docs describe. The rest show their keycap name.
    public static let commandTitles: [String: String] = [
        "APPR": "Approve", "REJ": "Decline", "NEW": "New chat", "SPLIT": "Fork", "MIC": "Mic", "CODEX": "Send",
        "FAST": "Fast mode", "PLAN": "Permission mode", "FORWARD": "Next session", "BACK": "Previous session",
        "SIDEBAR": "Sidebar", "NEXT": "Next answer", "PREV": "Previous answer", "PICK": "Pick answer",
        "PADSETTINGS": "Open the config file", "LOCK": "Lock the Mac",
    ]

    /// What the MicroBridge window and the panel in Orca call each control.
    public static let controlTitles: [String: String] = [
        "AG": "Agent Keys", "ACT06": "Key 7", "ACT07": "Key 8", "ACT08": "Key 9", "ACT09": "Key 10", "WIDE": "Wide key",
        "ACT12": "Key 12", "DIAL": "Dial", "STICK": "Stick",
    ]
}

/// What a command does in each app, read and changed in the file. The MicroBridge window and
/// the bridge (for the panel in Orca) both change commands through here, so they agree.
extension ConfigFile {
    /// The bridge's own settings, as a file.
    public static let builtIn = ConfigFile(text: Config.defaultFileText)

    /// The actions in a binding as the file writes it: one action or a list. `none` is left out.
    public static func spellings(_ value: JSONValue?) -> [String] {
        let texts: [String]
        switch value {
        case let .string(text)?: texts = [text]
        case let .array(items)?: texts = items.compactMap(\.string)
        default: texts = []
        }
        return texts.filter { Action.parse($0) != Action.none }
    }

    /// One action is written as a string, several as a list.
    public static func binding(_ actions: [String]) -> JSONValue {
        actions.count == 1 ? .string(actions[0]) : .array(actions.map(JSONValue.string))
    }

    /// A control or a command target as one list per trigger. An action or a list on its own
    /// is the press.
    public static func triggerLists(_ value: JSONValue?) -> [(trigger: String, actions: [String])] {
        guard let value else { return [] }
        if case let .object(pairs) = value { return pairs.map { ($0.0, spellings($0.1)) } }
        return [("press", spellings(value))]
    }

    /// The name the file itself has for a command. The bridge reads names in any case.
    public func commandKey(_ name: String) -> String {
        if case let .object(pairs)? = value(at: ["commands"]),
           let own = pairs.first(where: { $0.0.uppercased() == name }) {
            return own.0
        }
        return name
    }

    /// A command as targets, whichever of its forms the file uses: an action, a list or an
    /// object of triggers is what it does everywhere. From `defaults` when this file leaves
    /// the command out.
    public func commandEntry(_ name: String, defaults: ConfigFile?) -> [(String, JSONValue)] {
        guard let value = value(at: ["commands", commandKey(name)]) ?? defaults?.value(at: ["commands", name]) else { return [] }
        if case let .object(pairs) = value, pairs.isEmpty || !pairs.allSatisfy({ Config.triggers.contains($0.0) }) {
            return pairs
        }
        return [("default", value)]
    }

    /// What a command does in one target (an app group, a bundle id or "default"), one list
    /// per trigger.
    public func commandLists(_ name: String, target: String, defaults: ConfigFile?) -> [(trigger: String, actions: [String])] {
        Self.triggerLists(commandEntry(name, defaults: defaults).first { $0.0 == target }?.1)
    }

    /// Replaces what a command does on one trigger in one target. An empty list removes it.
    /// The command's other parts are written back as they are, because a command the file
    /// mentions does only what the file says.
    public mutating func setCommand(_ name: String, target: String, trigger: String = "press", actions: [String],
                                    defaults: ConfigFile?) {
        let kept = actions.filter { Action.parse($0) != Action.none }
        var entry = commandEntry(name, defaults: defaults)
        var lists = Self.triggerLists(entry.first { $0.0 == target }?.1).filter { !$0.actions.isEmpty }
        if let index = lists.firstIndex(where: { $0.trigger == trigger }) {
            if kept.isEmpty { lists.remove(at: index) } else { lists[index].actions = kept }
        } else if !kept.isEmpty {
            lists.append((trigger, kept))
        }
        let value: JSONValue? = lists.isEmpty
            ? nil : lists.count == 1 && lists[0].trigger == "press" ? Self.binding(lists[0].actions)
            : .object(lists.map { ($0.trigger, Self.binding($0.actions)) })
        if let index = entry.firstIndex(where: { $0.0 == target }) {
            if let value { entry[index].1 = value } else { entry.remove(at: index) }
        } else if let value {
            entry.append((target, value))
        }
        set(.object(entry), at: ["commands", commandKey(name)])
    }
}
