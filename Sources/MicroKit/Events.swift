import Foundation

/// Something the pad reported on its own.
public enum PadEvent: Sendable, Equatable {
    /// A key, the dial or the touch strip. `name` is the pad's code, e.g. `AG03`, `ACT07`.
    case key(name: String, action: Int?, agent: Int?)
    /// Joystick position: angle and distance from center, both 0…1.
    case joystick(angle: Double, distance: Double)
    /// A notification this project does not know yet. Logged so it can be learned.
    case unknown(method: String, params: JSONValue)

    public init(method: String, params: JSONValue) {
        switch method {
        case "v.oai.hid":
            self = .key(name: params["k"]?.string ?? "?", action: params["act"]?.int, agent: params["ag"]?.int)
        case "v.oai.rad":
            self = .joystick(angle: params["a"]?.double ?? 0, distance: params["d"]?.double ?? 0)
        default:
            self = .unknown(method: method, params: params)
        }
    }

    /// The Agent Key slot (0…5) for `AG00`…`AG05`, else nil.
    public var agentSlot: Int? {
        guard case let .key(name, _, _) = self, name.count == 4, name.hasPrefix("AG0"),
              let digit = Int(name.suffix(1)), (0 ... 5).contains(digit) else { return nil }
        return digit
    }
}

/// The pad's answer to `device.status`.
public struct DeviceStatus: Sendable, Equatable {
    public var firmware: String?
    public var profile: Int?
    public var layer: Int?
    public var battery: Int?
    public var charging: Bool?

    public init(_ value: JSONValue) {
        firmware = value["version"]?.string
        profile = value["profile_index"]?.int
        layer = value["layer_index"]?.int
        battery = value["battery"]?.int
        charging = value["is_charging"]?.bool
    }
}

/// Follows which layer the pad is on. A tap on its touch sensor cycles layers and the pad says
/// nothing about it, yet its keys, dial and joystick only report to us on the first layer.
public struct LayerWatch: Sendable, Equatable {
    /// The layer whose keys send `v.oai.hid`. `layer_index` counts from 1.
    public static let ours = 1

    public enum Change: Sendable, Equatable {
        /// The pad is on another layer, where its keys do not reach us.
        case away(Int)
        /// The pad is on our layer again.
        case back
    }

    public private(set) var layer: Int?

    public init() {}

    /// Takes a fresh reading and returns what is worth telling the user, if anything.
    public mutating func read(_ now: Int?) -> Change? {
        guard let now, now != layer else { return nil }
        let wasAway = layer.map { $0 != Self.ours } ?? false
        layer = now
        if now != Self.ours { return .away(now) }
        return wasAway ? .back : nil
    }

    /// Forgets the reading, for when the pad goes away.
    public mutating func reset() { layer = nil }
}

/// Follows the pad's battery. Warns once when the charge falls to the threshold while the pad is
/// not charging, and is ready to warn again after a charge.
public struct BatteryWatch: Sendable, Equatable {
    /// Readings wobble by a percent or two; the charge must climb this far past the threshold
    /// before a second warning.
    public static let margin = 5

    /// Percent at or below which to warn. Zero turns the warning off.
    public var threshold: Int
    public private(set) var warned = false

    public init(threshold: Int) {
        self.threshold = threshold
    }

    /// Takes a fresh reading and returns the charge to warn about, if any.
    public mutating func read(battery: Int?, charging: Bool?) -> Int? {
        guard threshold > 0, let battery else { return nil }
        if charging == true || battery > threshold + Self.margin {
            warned = false
            return nil
        }
        guard !warned, battery <= threshold else { return nil }
        warned = true
        return battery
    }
}

/// After a `click:` presses a button, the key that did it stays quiet for a moment. A second
/// press would otherwise go on to the key's next action and could answer a prompt that appears
/// just then, unread.
public struct ClickGuard: Sendable {
    /// How long a key stays quiet. Zero turns the guard off.
    public var seconds: Double
    private var until: [String: Date] = [:]

    public init(seconds: Double) {
        self.seconds = seconds
    }

    public mutating func landed(_ key: String, at now: Date = Date()) {
        guard seconds > 0 else { return }
        until[key] = now.addingTimeInterval(seconds)
    }

    public mutating func blocks(_ key: String, at now: Date = Date()) -> Bool {
        guard let end = until[key] else { return false }
        if seconds > 0, now < end { return true }
        until[key] = nil
        return false
    }
}
