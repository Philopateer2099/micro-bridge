import PadWire
/// The pad methods this project sends, from PadWire. Named here so this module's `Method`
/// wins over the Objective-C runtime's.
public typealias Method = PadWire.Method

public struct RPCError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: Int
    public let message: String
    public var description: String { "pad error \(code): \(message)" }
}

public enum Incoming: Sendable, Equatable {
    /// `method` is echoed by the pad's firmware. Every app with the pad open sees every reply,
    /// so match on id **and** method.
    case response(id: String, method: String?, result: JSONValue?, error: RPCError?)
    case notification(method: String, params: JSONValue)
}

public enum RPC {
    /// Request text as the vendor app sends it: `{"method":…,"params":…,"id":N}`, no
    /// `jsonrpc` field, no trailing newline, non-ASCII escaped.
    public static func request(_ method: Method, params: JSONValue = .null, id: Int) -> String {
        let body = JSONValue.object([
            ("method", .string(method.rawValue)),
            ("params", params),
            ("id", .number(Double(id))),
        ])
        return asciiEscaped(body.serialized)
    }

    /// Reads one decoded message. The pad may use short keys: `i` for `id`, `m` for `method`,
    /// `p` for `params`.
    public static func decode(_ value: JSONValue) -> Incoming? {
        let idValue = value["id"] ?? value["i"]
        let id: String? = switch idValue {
        case let .number(n)?: JSONValue.number(n).int.map(String.init) ?? String(n)
        case let .string(s)?: s
        default: nil
        }
        if let id {
            var error: RPCError?
            if let e = value["error"] {
                error = RPCError(code: e["code"]?.int ?? 0, message: e["message"]?.string ?? "unknown")
            }
            return .response(id: id, method: (value["method"] ?? value["m"])?.string,
                             result: value["result"], error: error)
        }
        if let method = (value["method"] ?? value["m"])?.string {
            return .notification(method: method, params: value["params"] ?? value["p"] ?? .null)
        }
        return nil
    }
}

/// Turns RPC-channel lines into messages. A message can span several lines; lines are joined
/// from the first `{` until the text parses, as the vendor app does.
///
/// The pad sometimes sends a line that is cut short or run together with another. Such text
/// never parses, so it must not hold up what follows: a later line that stands on its own
/// replaces it, and it is dropped after a few lines in any case.
public struct MessageAssembler: Sendable {
    /// How many lines one message may span.
    public static let maxLines = 4

    private var pending = ""
    private var joined = 0
    /// Text given up on since the last `takeDropped()`.
    private var dropped: [String] = []

    public init() {}

    public mutating func feed(line: String) -> Incoming? {
        if !pending.isEmpty {
            if let value = JSONValue.parse(pending + line) {
                reset()
                return RPC.decode(value)
            }
            if let own = Self.message(in: line), let value = JSONValue.parse(own) {
                drop()
                return RPC.decode(value)
            }
            pending += line
            joined += 1
            if joined >= Self.maxLines || pending.utf8.count > LineAssembler.maxLine { drop() }
            return nil
        }
        guard let text = Self.message(in: line) else { return nil }
        guard let value = JSONValue.parse(text) else {
            pending = text
            joined = 1
            return nil
        }
        return RPC.decode(value)
    }

    /// Unreadable text the assembler gave up on, for the log. Empties the list.
    public mutating func takeDropped() -> [String] {
        defer { dropped = [] }
        return dropped
    }

    private static func message(in line: String) -> String? {
        line.firstIndex(of: "{").map { String(line[$0...]) }
    }

    private mutating func drop() {
        if dropped.count < 8 { dropped.append(pending) }
        reset()
    }

    private mutating func reset() {
        pending = ""
        joined = 0
    }
}
