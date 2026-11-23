import Foundation

/// Turns the pad's raw events into named triggers the config can bind:
/// `ACT07.press`, `AG.doubleTap`, `WIDE.release`, `DIAL.cw`, `DIAL.hold`, `STICK.up`.
public struct Gestures: Sendable {
    public struct Fired: Sendable, Equatable {
        public let control: String
        public let trigger: String
        /// The Agent Key (0…5) when `control` is `AG`.
        public let slot: Int?

        public init(_ control: String, _ trigger: String, slot: Int? = nil) {
            self.control = control
            self.trigger = trigger
            self.slot = slot
        }
    }

    private struct Down {
        var since: TimeInterval
        var control: String
        var slot: Int?
        var held = false
        /// Its press has not fired yet: it fires when the key comes up before a hold.
        var pending = false
    }

    /// A second press this soon after the first is a double tap (ChatGPT uses the same 350 ms).
    public var doubleTapSeconds = 0.35
    public var holdSeconds = 0.5
    /// The stick fires past this distance from center, and re-arms once back inside `stickRearm`.
    public var stickFire = 0.5
    public var stickRearm = 0.3

    private var down: [String: Down] = [:]
    private var lastPress: [String: TimeInterval] = [:]
    private var wide: Set<String> = []
    private var stickArmed = true

    public init() {}

    public var hasKeysDown: Bool { !down.isEmpty }

    /// Which way the stick points, or nil near the center. Angles are the pad's: 0 right,
    /// 0.25 down, 0.5 left, 0.75 up.
    public static func direction(angle: Double, distance: Double, threshold: Double = 0.5) -> String? {
        guard distance >= threshold else { return nil }
        if angle >= 0.625, angle < 0.875 { return "up" }
        if angle >= 0.125, angle < 0.375 { return "down" }
        if angle >= 0.375, angle < 0.625 { return "left" }
        return "right"
    }

    /// `hasDoubleTap` says whether a control has a double-tap action; without one, a quick
    /// second press is just another press. `waitsForHold` says whether a control's press should
    /// wait for the key to come up, so that holding it fires `hold` alone and not `press` too.
    public mutating func handle(_ event: PadEvent, at now: TimeInterval, waitsForHold: (String) -> Bool = { _ in false },
                                hasDoubleTap: (String) -> Bool) -> [Fired] {
        switch event {
        case let .key(name, action, _):
            if name == "ENC_CW" || name == "ENC_CC" {
                return action == 2 ? [Fired("DIAL", name == "ENC_CW" ? "cw" : "ccw")] : []
            }
            guard let action, action == 0 || action == 1 else { return [] }
            let pressed = action == 1
            if name == "ENC_CLK" {
                return key("DIAL", control: "DIAL", slot: nil, pressed: pressed, now, waitsForHold, hasDoubleTap)
            }
            if let slot = event.agentSlot {
                return key(name, control: "AG", slot: slot, pressed: pressed, now, waitsForHold, hasDoubleTap)
            }
            var fired = key(name, control: name, slot: nil, pressed: pressed, now, waitsForHold, hasDoubleTap)
            // The wide key closes two switches. `WIDE` goes down with the first and up with the last.
            if name == "ACT10" || name == "ACT11" {
                let wasUp = wide.isEmpty
                if pressed { wide.insert(name) } else { wide.remove(name) }
                if pressed, wasUp {
                    fired += key("WIDE", control: "WIDE", slot: nil, pressed: true, now, waitsForHold, hasDoubleTap)
                } else if !pressed, wide.isEmpty, !wasUp {
                    fired += key("WIDE", control: "WIDE", slot: nil, pressed: false, now, waitsForHold, hasDoubleTap)
                }
            }
            return fired

        case let .joystick(angle, distance):
            if distance < stickRearm { stickArmed = true }
            guard stickArmed, let direction = Self.direction(angle: angle, distance: distance, threshold: stickFire) else {
                return []
            }
            stickArmed = false
            return [Fired("STICK", direction)]

        case .unknown:
            return []
        }
    }

    /// Call while keys are down; fires `hold` once per press.
    public mutating func tick(at now: TimeInterval) -> [Fired] {
        var fired: [Fired] = []
        for name in down.keys.sorted() {
            guard var state = down[name], !state.held, now - state.since >= holdSeconds else { continue }
            state.held = true
            down[name] = state
            fired.append(Fired(state.control, "hold", slot: state.slot))
        }
        return fired
    }

    private mutating func key(_ name: String, control: String, slot: Int?, pressed: Bool, _ now: TimeInterval,
                              _ waitsForHold: (String) -> Bool, _ hasDoubleTap: (String) -> Bool) -> [Fired] {
        if pressed {
            guard down[name] == nil else { return [] }
            down[name] = Down(since: now, control: control, slot: slot)
            if let last = lastPress[name], now - last <= doubleTapSeconds, hasDoubleTap(control) {
                lastPress[name] = nil
                return [Fired(control, "doubleTap", slot: slot)]
            }
            lastPress[name] = now
            if waitsForHold(control) {
                down[name]?.pending = true
                return []
            }
            return [Fired(control, "press", slot: slot)]
        }
        guard let state = down.removeValue(forKey: name) else { return [] }
        let release = Fired(control, "release", slot: slot)
        // Up before the hold: this was a press after all.
        return state.pending && !state.held ? [Fired(control, "press", slot: slot), release] : [release]
    }
}

/// The stick as a scroll wheel: how far it is pushed up or down sets how fast it scrolls.
public struct StickScroll: Sendable {
    /// Closer to the center than this, the stick counts as let go.
    public static let deadZone = 0.15
    /// Points a second just past the dead zone, and at full push. Between them speed grows with
    /// the square of the push, so a small push reads slowly and a full one flies.
    public static let slowest = 60.0
    public static let fastest = 800.0
    /// This long without word from the stick, scrolling stops, in case its let-go never came. The
    /// stick reports only when it moves, so a push held still goes quiet: this must be long.
    public static let silence = 20.0

    private var carry = 0.0

    public init() {}

    /// How fast the stick asks to scroll, in points a second, positive up. Nil near the center
    /// and when it is pushed left or right.
    public static func speed(angle: Double, distance: Double) -> Double? {
        guard let way = Gestures.direction(angle: angle, distance: distance, threshold: deadZone),
              way == "up" || way == "down" else { return nil }
        let push = min(1, (distance - deadZone) / (1 - deadZone))
        let speed = slowest + (fastest - slowest) * push * push
        return way == "up" ? speed : -speed
    }

    /// The whole points to scroll after `seconds` at `speed`. The fraction left over waits for
    /// the next step, so a slow push still moves.
    public mutating func step(speed: Double, seconds: Double) -> Double {
        carry += speed * seconds
        let whole = carry.rounded(.towardZero)
        carry -= whole
        return whole
    }

    public mutating func reset() {
        carry = 0
    }
}
