import Foundation

/// Reads the end of a Claude Code session record. Stopping a turn by hand (Escape, or declining
/// a question or a permission prompt) fires no hook, so the record is the only place that says
/// the session is no longer busy or waiting.
public enum Transcript {
    /// How Claude Code words the person's entry when they stop a turn.
    static let marker = "[Request interrupted by user"

    /// When the person stopped the turn, if that is the latest thing either side said in this
    /// tail of the record.
    public static func interruptedAt(tail: String) -> Date? {
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            // The first line of a tail may be cut, and the record holds other kinds of entry.
            guard let entry = JSONValue.parse(String(line)), let kind = entry["type"]?.string,
                  kind == "user" || kind == "assistant" else { continue }
            guard kind == "user", let said = text(of: entry["message"]?["content"]), said.hasPrefix(marker),
                  let stamp = entry["timestamp"]?.string else { return nil }
            return date(stamp)
        }
        return nil
    }

    /// The last `bytes` of a file, starting at a whole line.
    public static func tail(of path: String, bytes: Int = 32 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard start > 0, let newline = text.firstIndex(of: "\n") else { return text }
        return String(text[text.index(after: newline)...])
    }

    private static func text(of content: JSONValue?) -> String? {
        switch content {
        case let .string(text)?: return text
        case let .array(parts)?:
            return parts.first { $0["type"]?.string == "text" }?["text"]?.string
        default: return nil
        }
    }

    private static func date(_ stamp: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }
}
