import CoreGraphics
import Foundation

/// Catches ⌃⌘Q, the Mac's lock shortcut, so the pad's lights can go off first: once the Mac is
/// locked, macOS refuses every write to the pad. The shortcut is held back, the daemon turns the
/// lights off, and then the same shortcut is typed again so the Mac locks. It is typed again
/// after `wait` seconds at most, whatever the daemon is doing, so ⌃⌘Q always locks.
///
/// The tap sees every key press on the Mac. It reads only each one's key code, modifiers and
/// mark, keeps nothing and logs nothing, and lets every other key through untouched. It runs on
/// its own thread so that a busy daemon never holds up the keyboard. Secure text entry (a
/// password field, Terminal's Secure Keyboard Entry) hides keys from it: ⌃⌘Q then locks as usual
/// and the lights stay as they were.
public final class LockShortcut: @unchecked Sendable {
    /// The Q key.
    static let q: Int64 = 12
    /// Marks a ⌃⌘Q this bridge types, so the tap lets it through.
    static let mark: Int64 = 0x4D42_4C4B
    /// The longest the lock waits for the lights.
    static let wait: TimeInterval = 2.5

    /// ⌃⌘Q exactly: with Shift or Option it is some other shortcut.
    static func isLockShortcut(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskControl) && flags.contains(.maskCommand)
            && !flags.contains(.maskShift) && !flags.contains(.maskAlternate)
    }

    /// Types ⌃⌘Q with this bridge's mark: the Mac locks.
    public static func press() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(q), keyDown: down) else { continue }
            event.flags = [.maskControl, .maskCommand]
            event.setIntegerValueField(.eventSourceUserData, value: mark)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Runs on the main thread when ⌃⌘Q is caught. Call `darkened()` once the lights are off.
    private let caught: @Sendable @MainActor () -> Void
    private let guardian = NSLock()
    private var tap: CFMachPort?
    private var on = false
    /// The Q of a held-back ⌃⌘Q is down: its repeats and its release are held back too.
    private var holding = false
    /// Signalled when the lights are off, while a lock waits for them.
    private var pending: DispatchSemaphore?

    public init(caught: @escaping @Sendable @MainActor () -> Void) {
        self.caught = caught
    }

    /// Whether ⌃⌘Q is caught. Off, every key passes as if there were no tap.
    public var enabled: Bool {
        get { guardian.withLock { on } }
        set {
            let tap = guardian.withLock { () -> CFMachPort? in
                on = newValue
                return self.tap
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: newValue) }
        }
    }

    public var started: Bool { guardian.withLock { tap != nil } }

    /// Puts the tap in place. False when macOS refuses it, as it does without Accessibility.
    public func start() -> Bool {
        if started { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let made = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: lockShortcutCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let enable = guardian.withLock { () -> Bool in
            tap = made
            return on
        }
        let loop = Loop(tap: made, source: CFMachPortCreateRunLoopSource(nil, made, 0), enable: enable)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), loop.source, .commonModes)
            CGEvent.tapEnable(tap: loop.tap, enable: loop.enable)
            CFRunLoopRun()
        }
        thread.name = "lock shortcut"
        thread.start()
        return true
    }

    /// The lights are off: the lock may go ahead.
    public func darkened() {
        guardian.withLock { pending }?.signal()
    }

    /// True to hold the event back. On the tap's thread: it must never wait.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a slow tap off. Turn it back on if it should be.
            let (tap, on) = guardian.withLock { (self.tap, self.on) }
            if let tap, on { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown, .keyUp:
            break
        default:
            return false
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.q,
              event.getIntegerValueField(.eventSourceUserData) != Self.mark else { return false }
        if type == .keyUp {
            return guardian.withLock {
                defer { holding = false }
                return holding
            }
        }
        guard Self.isLockShortcut(event.flags) else { return false }
        let done: DispatchSemaphore? = guardian.withLock {
            let repeated = holding
            holding = true
            // A key held down repeats; one lock is enough.
            guard !repeated, pending == nil else { return nil }
            let done = DispatchSemaphore(value: 0)
            pending = done
            return done
        }
        guard let done else { return true }
        let caught = self.caught
        DispatchQueue.main.async { MainActor.assumeIsolated { caught() } }
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            _ = done.wait(timeout: .now() + Self.wait)
            Self.press()
            guardian.withLock { pending = nil }
        }
        return true
    }
}

/// What the tap's thread needs, made on the thread that starts it.
private struct Loop: @unchecked Sendable {
    let tap: CFMachPort
    let source: CFRunLoopSource
    let enable: Bool
}

private func lockShortcutCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                  info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let shortcut = Unmanaged<LockShortcut>.fromOpaque(info).takeUnretainedValue()
    return shortcut.handle(type, event) ? nil : Unmanaged.passUnretained(event)
}
