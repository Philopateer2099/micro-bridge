public enum Effect: Int, Sendable, CaseIterable {
    case off = 0
    case solid = 1
    case snake = 2
    case rainbow = 3
    case breath = 4
    case gradient = 5
    case shallowBreath = 6
}

/// One Agent Key's light. Only `slot` is required; nil fields stay as they are on the pad.
public struct SlotLight: Sendable, Equatable {
    public var slot: Int
    public var color: UInt32?
    public var brightness: Double?
    public var effect: Effect?
    public var speed: Double?
    public var syncKeys: Bool?
    public var syncAmbient: Bool?

    public init(slot: Int, color: UInt32? = nil, brightness: Double? = nil, effect: Effect? = nil,
                speed: Double? = nil, syncKeys: Bool? = nil, syncAmbient: Bool? = nil) {
        self.slot = slot
        self.color = color
        self.brightness = brightness
        self.effect = effect
        self.speed = speed
        self.syncKeys = syncKeys
        self.syncAmbient = syncAmbient
    }

    public var json: JSONValue {
        var pairs: [(String, JSONValue)] = [("id", .number(Double(slot)))]
        if let color { pairs.append(("c", .number(Double(color)))) }
        if let brightness { pairs.append(("b", .number(brightness))) }
        if let effect { pairs.append(("e", .number(Double(effect.rawValue)))) }
        if let speed { pairs.append(("s", .number(speed))) }
        if let syncKeys { pairs.append(("sk", .number(syncKeys ? 1 : 0))) }
        if let syncAmbient { pairs.append(("sa", .number(syncAmbient ? 1 : 0))) }
        return .object(pairs)
    }
}

/// One lighting zone: the ambient ring or the key backlight.
public struct ZoneLight: Sendable, Equatable {
    public var effect: Effect
    public var brightness: Double
    public var speed: Double
    public var color: UInt32

    public init(effect: Effect, brightness: Double, speed: Double, color: UInt32) {
        self.effect = effect
        self.brightness = brightness
        self.speed = speed
        self.color = color
    }

    public static let off = ZoneLight(effect: .off, brightness: 0, speed: 0, color: 0)

    public var json: JSONValue {
        .object([
            ("e", .number(Double(effect.rawValue))),
            ("b", .number(brightness)),
            ("s", .number(speed)),
            ("m", .number(0)),
            ("c", .number(Double(color))),
        ])
    }
}

/// What an agent is doing, as the pad shows it.
public enum AgentStatus: String, Sendable, CaseIterable {
    case working
    case needsYou = "needs-you"
    case idle
    case done
    case failed
    case off

    /// Colors match the ChatGPT app so the pad reads the same in both.
    public var color: UInt32 {
        switch self {
        case .working: 0x304FFE
        case .needsYou: 0xFF6D00
        case .idle: 0xFFFFFF
        case .done: 0x00FF4C
        case .failed: 0xFF0033
        case .off: 0
        }
    }

    /// `color` overrides the default for this status.
    public func light(slot: Int, brightness: Double = 1, selected: Bool = false, color: UInt32? = nil) -> SlotLight {
        if self == .off {
            return SlotLight(slot: slot, color: 0, brightness: 0, effect: .off, speed: 0,
                             syncKeys: false, syncAmbient: false)
        }
        let pulse = selected || self == .needsYou
        return SlotLight(slot: slot, color: color ?? self.color, brightness: brightness,
                         effect: pulse ? .breath : .solid, speed: pulse ? 0.4 : 0,
                         syncKeys: false, syncAmbient: false)
    }
}
