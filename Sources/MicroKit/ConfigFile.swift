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
