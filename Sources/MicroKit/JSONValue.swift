import Foundation

/// A JSON value. Encoding is done by hand (`serialized`) so the bytes sent to the pad are
/// predictable: integral numbers print without a decimal point, key order is the order given.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    /// Ordered key/value pairs. The pad's parser is small; keep output close to what the
    /// vendor app sends.
    case object([(String, JSONValue)])

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(a), .bool(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.array(a), .array(b)): a == b
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: false
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first { $0.0 == key }?.1
    }

    public var string: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var double: Double? {
        if case let .number(n) = self { return n }
        return nil
    }

    public var int: Int? {
        guard case let .number(n) = self, n.rounded() == n, abs(n) < 1e15 else { return nil }
        return Int(n)
    }

    public var bool: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }
}

// MARK: - Encoding

extension JSONValue {
    /// Compact JSON text. Non-ASCII characters are left as-is; `asciiEscaped` handles those.
    public var serialized: String {
        var out = ""
        write(into: &out)
        return out
    }

    /// JSON text spread over lines, two spaces a level, every array item and object member on
    /// its own line: the way Claude Code writes its settings file, so a change to it stays small.
    public var indented: String {
        var out = ""
        writeIndented(into: &out, depth: 0)
        return out
    }

    private func writeIndented(into out: inout String, depth: Int) {
        let inner = String(repeating: "  ", count: depth + 1)
        let outer = String(repeating: "  ", count: depth)
        switch self {
        case let .array(items) where !items.isEmpty:
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += inner
                item.writeIndented(into: &out, depth: depth + 1)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += outer + "]"
        case let .object(pairs) where !pairs.isEmpty:
            out += "{\n"
            for (i, (key, value)) in pairs.enumerated() {
                out += inner
                Self.quote(key, into: &out)
                out += ": "
                value.writeIndented(into: &out, depth: depth + 1)
                out += i < pairs.count - 1 ? ",\n" : "\n"
            }
            out += outer + "}"
        default:
            write(into: &out)
        }
    }

    /// This object with `key` set to `value`: in its place if it is there, last if not.
    func setting(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case var .object(pairs) = self else { return self }
        if let at = pairs.firstIndex(where: { $0.0 == key }) {
            pairs[at].1 = value
        } else {
            pairs.append((key, value))
        }
        return .object(pairs)
    }

    private func write(into out: inout String) {
        switch self {
        case .null: out += "null"
        case let .bool(b): out += b ? "true" : "false"
        case let .number(n): out += Self.format(n)
        case let .string(s): Self.quote(s, into: &out)
        case let .array(items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case let .object(pairs):
            out += "{"
            for (i, (key, value)) in pairs.enumerated() {
                if i > 0 { out += "," }
                Self.quote(key, into: &out)
                out += ":"
                value.write(into: &out)
            }
            out += "}"
        }
    }

    static func format(_ n: Double) -> String {
        precondition(n.isFinite, "JSON cannot carry \(n)")
        if n.rounded() == n, abs(n) < 1e15 { return String(Int64(n)) }
        return String(n) // Swift prints the shortest form that round-trips, e.g. 0.4
    }

    static func quote(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

// MARK: - Decoding

extension JSONValue {
    /// Parses JSON text. Returns nil for anything that is not a complete JSON value.
    public static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return from(object)
    }

    private static func from(_ any: Any) -> JSONValue? {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            // NSNumber hides booleans; CFBoolean is the tell.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let a as [Any]:
            var items: [JSONValue] = []
            for element in a {
                guard let value = from(element) else { return nil }
                items.append(value)
            }
            return .array(items)
        case let d as [String: Any]:
            var pairs: [(String, JSONValue)] = []
            for key in d.keys.sorted() {
                guard let value = from(d[key]!) else { return nil }
                pairs.append((key, value))
            }
            return .object(pairs)
        default: return nil
        }
    }
}

// MARK: - Decoding, keys in the order written

extension JSONValue {
    /// Parses JSON text and keeps each object's keys in the order the text has them, so a file
    /// can be changed and written back without shuffling it. `parse` sorts them instead.
    /// A key written twice keeps its first place and its last value.
    public static func parseKeepingOrder(_ text: String) -> JSONValue? {
        var reader = OrderedReader(bytes: Array(text.utf8))
        guard let value = reader.value(depth: 0) else { return nil }
        reader.skipSpace()
        return reader.atEnd ? value : nil
    }

    private struct OrderedReader {
        let bytes: [UInt8]
        var at = 0

        var atEnd: Bool { at == bytes.count }

        mutating func skipSpace() {
            while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        }

        private mutating func take(_ byte: UInt8) -> Bool {
            guard at < bytes.count, bytes[at] == byte else { return false }
            at += 1
            return true
        }

        private mutating func take(word: String) -> Bool {
            let wanted = Array(word.utf8)
            guard at + wanted.count <= bytes.count, Array(bytes[at ..< at + wanted.count]) == wanted else { return false }
            at += wanted.count
            return true
        }

        mutating func value(depth: Int) -> JSONValue? {
            guard depth < 64 else { return nil }
            skipSpace()
            guard at < bytes.count else { return nil }
            switch bytes[at] {
            case UInt8(ascii: "{"): return object(depth: depth)
            case UInt8(ascii: "["): return array(depth: depth)
            case UInt8(ascii: "\""): return string().map(JSONValue.string)
            case UInt8(ascii: "t"): return take(word: "true") ? .bool(true) : nil
            case UInt8(ascii: "f"): return take(word: "false") ? .bool(false) : nil
            case UInt8(ascii: "n"): return take(word: "null") ? .null : nil
            default: return number()
            }
        }

        private mutating func object(depth: Int) -> JSONValue? {
            at += 1
            var pairs: [(String, JSONValue)] = []
            skipSpace()
            if take(UInt8(ascii: "}")) { return .object(pairs) }
            while true {
                skipSpace()
                guard let key = string() else { return nil }
                skipSpace()
                guard take(UInt8(ascii: ":")), let item = value(depth: depth + 1) else { return nil }
                if let index = pairs.firstIndex(where: { $0.0 == key }) {
                    pairs[index].1 = item
                } else {
                    pairs.append((key, item))
                }
                skipSpace()
                if take(UInt8(ascii: ",")) { continue }
                return take(UInt8(ascii: "}")) ? .object(pairs) : nil
            }
        }

        private mutating func array(depth: Int) -> JSONValue? {
            at += 1
            var items: [JSONValue] = []
            skipSpace()
            if take(UInt8(ascii: "]")) { return .array(items) }
            while true {
                guard let item = value(depth: depth + 1) else { return nil }
                items.append(item)
                skipSpace()
                if take(UInt8(ascii: ",")) { continue }
                return take(UInt8(ascii: "]")) ? .array(items) : nil
            }
        }

        private mutating func string() -> String? {
            guard take(UInt8(ascii: "\"")) else { return nil }
            var units: [UInt16] = []
            var raw: [UInt8] = []
            func flush(_ raw: inout [UInt8], into units: inout [UInt16]) -> Bool {
                guard !raw.isEmpty else { return true }
                guard let text = String(bytes: raw, encoding: .utf8) else { return false }
                units.append(contentsOf: text.utf16)
                raw.removeAll(keepingCapacity: true)
                return true
            }
            while at < bytes.count {
                let byte = bytes[at]
                at += 1
                switch byte {
                case UInt8(ascii: "\""):
                    guard flush(&raw, into: &units) else { return nil }
                    return Self.text(units)
                case UInt8(ascii: "\\"):
                    guard flush(&raw, into: &units), at < bytes.count else { return nil }
                    let escape = bytes[at]
                    at += 1
                    switch escape {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): units.append(UInt16(escape))
                    case UInt8(ascii: "b"): units.append(0x08)
                    case UInt8(ascii: "f"): units.append(0x0C)
                    case UInt8(ascii: "n"): units.append(0x0A)
                    case UInt8(ascii: "r"): units.append(0x0D)
                    case UInt8(ascii: "t"): units.append(0x09)
                    case UInt8(ascii: "u"):
                        guard at + 4 <= bytes.count,
                              let unit = UInt16(String(decoding: bytes[at ..< at + 4], as: UTF8.self), radix: 16),
                              bytes[at ..< at + 4].allSatisfy({ $0 != UInt8(ascii: "+") && $0 != UInt8(ascii: "-") })
                        else { return nil }
                        units.append(unit)
                        at += 4
                    default: return nil
                    }
                case 0 ..< 0x20:
                    return nil
                default:
                    raw.append(byte)
                }
            }
            return nil
        }

        /// Nil for a lone half of a surrogate pair, which is not text.
        private static func text(_ units: [UInt16]) -> String? {
            var scalars = String.UnicodeScalarView()
            var rest = units.makeIterator()
            var decoder = UTF16()
            while true {
                switch decoder.decode(&rest) {
                case let .scalarValue(scalar): scalars.append(scalar)
                case .emptyInput: return String(scalars)
                case .error: return nil
                }
            }
        }

        private mutating func number() -> JSONValue? {
            let start = at
            func digits(_ reader: inout OrderedReader) -> Int {
                let from = reader.at
                while reader.at < reader.bytes.count, (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(reader.bytes[reader.at]) {
                    reader.at += 1
                }
                return reader.at - from
            }
            _ = take(UInt8(ascii: "-"))
            if take(UInt8(ascii: "0")) {
                // A leading zero stands alone.
            } else if digits(&self) == 0 {
                return nil
            }
            if take(UInt8(ascii: ".")), digits(&self) == 0 { return nil }
            if take(UInt8(ascii: "e")) || take(UInt8(ascii: "E")) {
                if !take(UInt8(ascii: "+")) { _ = take(UInt8(ascii: "-")) }
                if digits(&self) == 0 { return nil }
            }
            guard let number = Double(String(decoding: bytes[start ..< at], as: UTF8.self)), number.isFinite else { return nil }
            return .number(number)
        }
    }
}
