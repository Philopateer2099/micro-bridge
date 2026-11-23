import Foundation

/// The pad's 64-byte HID reports: `[0x06, channel, length, payload…]`.
public enum Framing {
    public static let reportID: UInt8 = 0x06
    public static let reportSize = 64
    public static let maxPayload = 61

    public enum Channel: UInt8, Sendable {
        case debug = 1
        case rpc = 2
    }

    /// An input report as the pad sent it, report ID first. macOS includes the ID byte for
    /// devices that number their reports; this adds it back if a driver ever strips it.
    public static func normalized(_ bytes: [UInt8], reportID id: UInt32) -> [UInt8] {
        guard id == UInt32(reportID), bytes.first != reportID, bytes.count < reportSize else { return bytes }
        return [reportID] + bytes
    }

    /// Splits a message into reports, 61 payload bytes each, zero padded.
    public static func reports(for message: [UInt8], channel: Channel = .rpc) -> [[UInt8]] {
        stride(from: 0, to: message.count, by: maxPayload).map { offset in
            let chunk = message[offset ..< min(offset + maxPayload, message.count)]
            var report = [UInt8](repeating: 0, count: reportSize)
            report[0] = reportID
            report[1] = channel.rawValue
            report[2] = UInt8(chunk.count)
            report.replaceSubrange(3 ..< 3 + chunk.count, with: chunk)
            return report
        }
    }
}

/// Collects report payloads per channel and hands back complete lines.
///
/// Bytes are buffered, not strings, so a UTF-8 character split across two reports survives.
public struct LineAssembler: Sendable {
    public struct Line: Sendable, Equatable {
        public let channel: UInt8
        public let text: String

        public init(channel: UInt8, text: String) {
            self.channel = channel
            self.text = text
        }
    }

    /// A line longer than this is junk from a desynced stream; drop it.
    public static let maxLine = 16 * 1024

    private var buffers: [UInt8: [UInt8]] = [:]

    public init() {}

    /// Feeds one input report (report ID byte first). Reports with another ID, or a length
    /// that runs past the report, are ignored.
    public mutating func feed(_ report: [UInt8]) -> [Line] {
        guard report.count >= 3, report[0] == Framing.reportID else { return [] }
        let channel = report[1]
        let length = Int(report[2])
        guard length <= Framing.maxPayload, 3 + length <= report.count else { return [] }

        var buffer = buffers[channel, default: []]
        buffer.append(contentsOf: report[3 ..< 3 + length])

        var lines: [Line] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let raw = buffer[..<newline]
            buffer.removeSubrange(...newline)
            let text = String(decoding: raw, as: UTF8.self).trimmingWhitespace()
            if !text.isEmpty { lines.append(Line(channel: channel, text: text)) }
        }
        if buffer.count > Self.maxLine { buffer.removeAll() }
        buffers[channel] = buffer
        return lines
    }
}

extension String {
    package func trimmingWhitespace() -> String {
        var scalars = Substring(self).unicodeScalars
        while let first = scalars.first, first.properties.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }
}

/// Replaces every non-ASCII character with `\uXXXX` (UTF-16, surrogate pairs above U+FFFF),
/// as the vendor app does before sending.
public func asciiEscaped(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.utf8.count)
    for scalar in text.unicodeScalars {
        if scalar.isASCII {
            out.unicodeScalars.append(scalar)
        } else {
            for unit in String(scalar).utf16 {
                out += String(format: "\\u%04x", unit)
            }
        }
    }
    return out
}
