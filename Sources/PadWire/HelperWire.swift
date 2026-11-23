import Foundation

/// What MicroBridge and its optional root helper say to each other over the helper's socket.
/// Each frame is one type byte, a 4-byte big-endian length, then that many bytes.
public enum HelperWire {
    /// Where the helper listens. `/var/run` belongs to root, so no other program can put a
    /// socket of its own there.
    public static let socketPath = "/var/run/micro-bridge-helper.sock"
    /// The largest frame either side accepts. A pad report is 64 bytes, a request a few hundred.
    public static let maxFrame = 16 * 1024
    /// The largest request MicroBridge may ask the helper to send.
    public static let maxRequest = 4096
    /// The `sent` answer to a request the helper will not write: kIOReturnNotPrivileged.
    public static let refusedRequest = Int32(bitPattern: 0xE000_02C1)

    public enum Frame: Equatable, Sendable {
        /// MicroBridge → helper: write this request to the pad.
        case send(String)
        /// MicroBridge → helper: true takes the pad for MicroBridge alone, false shares it.
        case hold(Bool)
        /// Helper → MicroBridge: the pad it opened.
        case info(PadInfo)
        /// Helper → MicroBridge: how the last `send` went, as an IOReturn (0 is success). A
        /// request the helper will not write comes back as `refusedRequest`.
        case sent(Int32)
        /// Helper → MicroBridge: whether it holds the pad now, and the IOReturn of the change.
        case holding(Bool, Int32)
        /// Helper → MicroBridge: one input report from the pad.
        case report([UInt8])
        /// Helper → MicroBridge: the pad went away.
        case gone
        /// Helper → MicroBridge: it will not serve this connection, and why. It hangs up next.
        case refused(String)

        var type: UInt8 {
            switch self {
            case .send: 0x01
            case .hold: 0x02
            case .info: 0x81
            case .sent: 0x82
            case .holding: 0x83
            case .report: 0x84
            case .gone: 0x85
            case .refused: 0x8F
            }
        }

        public var encoded: [UInt8] {
            let payload: [UInt8] = switch self {
            case let .send(text), let .refused(text): Array(text.utf8)
            case let .hold(on): [on ? 1 : 0]
            case let .info(info): (try? Array(JSONEncoder().encode(info))) ?? []
            case let .sent(code): bigEndian(code)
            case let .holding(on, code): [on ? 1 : 0] + bigEndian(code)
            case let .report(bytes): bytes
            case .gone: []
            }
            return [type] + bigEndian(Int32(payload.count)) + payload
        }

        init?(type: UInt8, payload: [UInt8]) {
            switch type {
            case 0x01: self = .send(String(decoding: payload, as: UTF8.self))
            case 0x02:
                guard payload.count == 1 else { return nil }
                self = .hold(payload[0] == 1)
            case 0x81:
                guard let info = try? JSONDecoder().decode(PadInfo.self, from: Data(payload)) else { return nil }
                self = .info(info)
            case 0x82:
                guard payload.count == 4 else { return nil }
                self = .sent(int32(payload[0 ..< 4]))
            case 0x83:
                guard payload.count == 5 else { return nil }
                self = .holding(payload[0] == 1, int32(payload[1 ..< 5]))
            case 0x84: self = .report(payload)
            case 0x85:
                guard payload.isEmpty else { return nil }
                self = .gone
            case 0x8F: self = .refused(String(decoding: payload, as: UTF8.self))
            default: return nil
            }
        }
    }

    /// Collects bytes from the socket and hands back whole frames. After a frame it cannot
    /// read, `broken` is set and it reads nothing more: the other side is not speaking this
    /// protocol, so the connection should close.
    public struct FrameReader: Sendable {
        private var buffer: [UInt8] = []
        public private(set) var broken = false

        public init() {}

        public mutating func feed(_ bytes: [UInt8]) -> [Frame] {
            guard !broken else { return [] }
            buffer += bytes
            var frames: [Frame] = []
            while buffer.count >= 5 {
                let length = Int(int32(buffer[1 ..< 5]))
                guard length >= 0, length <= HelperWire.maxFrame else {
                    broken = true
                    return frames
                }
                guard buffer.count >= 5 + length else { break }
                let payload = Array(buffer[5 ..< 5 + length])
                guard let frame = Frame(type: buffer[0], payload: payload) else {
                    broken = true
                    return frames
                }
                frames.append(frame)
                buffer.removeFirst(5 + length)
            }
            return frames
        }
    }

    /// The request the helper writes to the pad for `text`, or nil when it must not write it:
    /// too long, not one JSON object with only `method`, `params` and `id`, an id that is not a
    /// whole number, or a method outside `Method`. The text written is rebuilt from what was
    /// checked, so the pad cannot read anything else into it, such as a second `method`.
    public static func checkedRequest(_ text: String) -> String? {
        guard text.utf8.count <= maxRequest,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              Set(object.keys).isSubset(of: ["method", "params", "id"]),
              let name = object["method"] as? String, let method = Method(rawValue: name),
              let id = object["id"] as? NSNumber,
              CFGetTypeID(id) == CFNumberGetTypeID(), !CFNumberIsFloatType(id),
              (0 ... 1_000_000).contains(id.intValue)
        else { return nil }
        let params = object["params"] ?? NSNull()
        guard let paramsData = try? JSONSerialization.data(
            withJSONObject: params, options: [.fragmentsAllowed, .withoutEscapingSlashes, .sortedKeys]
        ) else { return nil }
        let paramsText = String(decoding: paramsData, as: UTF8.self)
        return asciiEscaped(#"{"method":"\#(method.rawValue)","params":\#(paramsText),"id":\#(id.intValue)}"#)
    }
}

private func bigEndian(_ value: Int32) -> [UInt8] {
    withUnsafeBytes(of: value.bigEndian) { Array($0) }
}

private func int32(_ bytes: ArraySlice<UInt8>) -> Int32 {
    bytes.reduce(Int32(0)) { ($0 << 8) | Int32($1) }
}
