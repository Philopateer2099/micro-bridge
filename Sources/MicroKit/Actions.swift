import AppKit
import CoreGraphics
import Foundation

/// macOS only lets an app type into other apps once the user allows it under
/// Privacy & Security > Accessibility.
public enum Accessibility {
    public static var granted: Bool { CGPreflightPostEventAccess() }

    /// Shows the system prompt if the user has not decided yet. Returns true if granted.
    @discardableResult
    public static func request() -> Bool { CGRequestPostEventAccess() }
}

/// Carries out the actions a config binds to controls.
@MainActor
public final class ActionRunner {
    public var log: (String) -> Void = { _ in }
    /// Bundle ids that may receive typed keys. Empty: whichever app is in front.
    public var keystrokeApps: [String] = []
    /// One `scroll:` step from a key, in points: about three lines.
    public static let scrollStep = 120.0

    private let source = CGEventSource(stateID: .hidSystemState)
    private var warnedAccess = false
    /// Keys held down by a `keydown:` action, by key code, each with its repeat timer.
    private var held: [UInt16: Timer] = [:]
    /// Option boxes a `choose:` just looked for and did not find, with when to look again.
    /// Walking a window takes around a tenth of a second, too long for every dial step.
    private var absent: [String: Date] = [:]
    private static let lookAgainAfter = 0.4
    /// Where a `choose:` last left a box's selection, by app and box. While the dial keeps
    /// turning, this stands in for what the app shows (which lags behind a fast dial) and the
    /// box itself is kept, so a step looks inside the box and not through the whole window.
    private var turning: [String: (index: Int?, box: AXUIElement?, at: Date)] = [:]
    /// A step this soon after the last one counts as the same turn of the dial.
    private static let sameTurn = 0.6
    /// How long a box found by one step may be reused without searching for it again.
    private static let boxKeeps = 5.0
    /// The box a `choose:` just found missing from the screen. A `click:` on the same box, later
    /// in the same list, need not search the window again.
    private var missed: (app: String, box: String, at: Date)?

    public init() {}

    /// The bundle id of the app in front.
    public static var frontApp: String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    /// `slot` and `session` say which Agent Key the action is about, when there is one.
    /// True when the action settled the press, so the rest of its list must not run.
    @discardableResult
    public func run(_ action: Action, slot: Int?, session: Session?) -> Bool {
        if case let .click(rule) = action { return click(rule) }
        if case let .choose(rule) = action { return choose(rule) }
        if case let .complete(box) = action { return complete(box) }
        switch action {
        case .none, .ack, .forget, .pin, .lock, .command, .click, .choose, .complete:
            // The daemon handles ack, forget, pin and lock, and replaces commands before they get here.
            break
        case let .scroll(up):
            scroll(up ? Self.scrollStep : -Self.scrollStep)
        case let .pane(left):
            movePointer(toPaneOn: left)
        case let .key(combo, phase, _):
            // A key that is already held must always come back up.
            guard mayType(checkApp: phase != .up) else { return false }
            switch phase {
            case .tap:
                post(combo, down: true)
                post(combo, down: false)
            case .down:
                hold(combo)
            case .up:
                release(combo)
            }
        case let .text(text):
            guard mayType(checkApp: true) else { return false }
            type(text)
        case let .shell(command):
            spawn("/bin/sh", ["-c", command], slot: slot, session: session)
        case let .open(target):
            spawn("/usr/bin/open", [target], slot: slot, session: session)
        case .jump:
            jump(to: session)
        case .focus:
            focus(session)
        }
        return false
    }

    // MARK: Choosing

    /// Moves the selection in the box the rule names. False when the app in front shows no
    /// such options, so the next action can run.
    private func choose(_ rule: OptionRule) -> Bool {
        guard mayType(checkApp: true), let app = Self.frontApp else { return false }
        let place = "\(app)|\(rule.box)|\(rule.option)"
        let now = Date()
        if let until = absent[place], now < until {
            // Still turning: do not stop to look until the dial rests.
            if rule.step != .mark { absent[place] = now.addingTimeInterval(Self.lookAgainAfter) }
            return false
        }
        let last = turning[place]
        let since = last.map { now.timeIntervalSince($0.at) } ?? .infinity
        let looked = ScreenButtons.card(rule, bundleID: app, in: since < Self.boxKeeps ? last?.box : nil)
        guard let card = looked.card else {
            absent[place] = now.addingTimeInterval(Self.lookAgainAfter)
            turning[place] = nil
            if !looked.boxShowing { missed = (app, rule.box, now) }
            return false
        }
        absent[place] = nil
        let recent = since < Self.sameTurn ? last?.index : nil
        let found = "\(looked.nodes) elements"
        if rule.step == .mark, let text = card.fieldText {
            // The focus is in the card's free-text answer. With text there, the press belongs to
            // the next action, the card's Next or Submit. With none it does nothing: an empty
            // answer is no answer, and a fast second press must not send one.
            guard text.isEmpty else { return false }
            log("choose:\(rule.spelling): nothing typed in the card's text field yet (\(found))")
            return true
        }
        if card.many {
            return highlight(rule, in: card, app: app, place: place, recent: recent, found: found)
        }
        // One answer: the press is not a mark, it belongs to the next action, the card's Submit.
        guard rule.step != .mark else { return false }
        let chosen = ScreenButtons.choose(in: card, step: rule.step, assuming: recent)
        turning[place] = (chosen.index, card.box, now)
        let took = "\(found), \(Int(Date().timeIntervalSince(now) * 1000)) ms"
        if let label = chosen.pressed {
            let how = chosen.took ? (chosen.presses > 1 ? ", \(chosen.presses) presses" : "") : ", \(chosen.presses) presses and it is still off"
            log("choose:\(rule.spelling): selected \"\(label.prefix(60))\" (\(took)\(how))")
        } else {
            log("choose:\(rule.spelling): stays where it is, \(chosen.options) options (\(took))")
        }
        return true
    }

    /// A card that takes several answers. A turn moves the keyboard focus from one answer to the
    /// next and ticks nothing; `mark` types Space on what has the focus, as a keyboard would.
    private func highlight(_ rule: OptionRule, in card: ScreenButtons.Card, app: String, place: String, recent: Int?, found: String) -> Bool {
        let started = Date()
        let lit = recent.flatMap { card.places.indices.contains($0) ? $0 : nil } ?? card.lit
        func took() -> String { "\(found), \(Int(Date().timeIntervalSince(started) * 1000)) ms" }
        if rule.step == .mark {
            // Nothing in the card has the focus: nothing to mark, so the next action may run.
            guard let lit else { return false }
            let before = card.places[lit]
            tap("space")
            turning[place] = (lit, card.box, Date())
            var result = ""
            if before.isOption {
                usleep(150_000)
                let after = ScreenButtons.card(rule, bundleID: app, in: card.box).card?.places
                if let after, after.indices.contains(lit), after[lit].label == before.label {
                    result = after[lit].on == before.on ? ": it did not change" : after[lit].on ? ": now ticked" : ": now unticked"
                    let others = after.indices.filter { $0 != lit && card.places.indices.contains($0) && after[$0].on != card.places[$0].on }
                    if !others.isEmpty { result += ", and \(others.count) other answers changed" }
                } else {
                    result = ": the card changed"
                }
            }
            log("choose:\(rule.spelling): typed Space on \"\(before.label.prefix(60))\"\(result) (\(took()))")
            return true
        }
        guard let target = OptionRule.stop(card.stops, from: lit, step: rule.step) else {
            turning[place] = (lit, card.box, Date())
            log("choose:\(rule.spelling): the highlight stays where it is (\(took()))")
            return true
        }
        guard card.focus(target) else {
            log("choose:\(rule.spelling): could not move the focus to \"\(card.places[target].label.prefix(60))\" (\(took()))")
            return true
        }
        var how = ""
        if lit == nil {
            // The focus has just come into the card. Once it is there, two arrow keys that
            // cancel out tell the app a keyboard is in use, so it draws its focus outline.
            if card.focusLanded(on: target) {
                tap("left")
                tap("right")
                how = ", focus moved into the card"
            } else {
                how = ", the focus did not arrive"
            }
        }
        turning[place] = (target, card.box, Date())
        log("choose:\(rule.spelling): highlighted \"\(card.places[target].label.prefix(60))\" (\(took())\(how))")
        return true
    }

    // MARK: Scrolling

    /// Scrolls by `points`, positive toward the top, as a mouse wheel does: whatever is under
    /// the pointer. The Claude app scrolls only for a wheel macOS aims at the window under the
    /// pointer; aiming it anywhere else either does nothing or moves the pointer there.
    public func scroll(_ points: Double) {
        guard points != 0, mayType(checkApp: false),
              let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                  wheel1: Int32(points.rounded()), wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Moves the pointer to the middle of the next pane that way in the front window, as moving
    /// the mouse there would, so that scrolling goes to that pane.
    public func movePointer(toPaneOn left: Bool) {
        let way = left ? "left" : "right"
        guard mayType(checkApp: false), let app = Self.frontApp else { return }
        let started = Date()
        let panes = ScreenButtons.panes(bundleID: app)
        let took = Int(Date().timeIntervalSince(started) * 1000)
        guard let pointer = CGEvent(source: nil)?.location,
              let pane = Panes.next(from: pointer, in: panes, left: left) else {
            log("pane:\(way): no pane that way (\(panes.count) in the window, \(took) ms)")
            return
        }
        let spot = Panes.spot(in: pane)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: spot, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        log("pane:\(way): pointer to the pane at x \(Int(pane.minX))…\(Int(pane.maxX)) (\(panes.count) in the window, \(took) ms)")
    }

    /// Locks the Mac with the shortcut a person would press, ⌃⌘Q, whichever app is in front.
    /// Marked, so the bridge's own ⌃⌘Q catcher lets it through. False without Accessibility.
    public func lockScreen() -> Bool {
        guard mayType(checkApp: false) else { return false }
        LockShortcut.press()
        return true
    }

    /// Types one key: down, then up.
    private func tap(_ name: String) {
        guard let combo = KeyCombo.parse(name) else { return }
        post(combo, down: true)
        post(combo, down: false)
    }

    // MARK: Clicking

    /// Presses the button the rule names in the app in front. False when there is none.
    private func click(_ rule: ButtonRule) -> Bool {
        guard mayType(checkApp: true), let app = Self.frontApp else { return false }
        if let missed, missed.app == app, missed.box == rule.box, Date().timeIntervalSince(missed.at) < 0.2 { return false }
        let found = ScreenButtons.find(rule, bundleID: app)
        let took = "\(found.nodes) elements, \(Int(found.seconds * 1000)) ms"
        guard let button = found.button else {
            let there = found.labels.prefix(6).map { "\"\($0.prefix(30))\"" }.joined(separator: ", ")
            let why = found.problem ?? (found.boxShowing
                ? "not among the \(found.candidates) buttons there\(there.isEmpty ? "" : ": \(there)")"
                : "its box is not on screen")
            log("click:\(rule.spelling): nothing to press, \(why) (\(took))")
            return false
        }
        let presses = rule.insist ? button.pressUntilGone(in: found.box) : (button.press() ? 1 : 0)
        let how = presses > 1 ? ", \(presses) presses" : ""
        log("click:\(rule.spelling): \(presses > 0 ? "pressed" : "could not press") \"\(button.label)\" (\(took)\(how))")
        return presses > 0
    }

    // MARK: Completing

    /// Fills the focused `box` with the suggestion it shows, when it holds nothing typed. Leaves
    /// the sending to the next action, so a box with no suggestion gets a plain Return. True
    /// only when it had to stop the press: the Return must not run.
    private func complete(_ box: String) -> Bool {
        guard mayType(checkApp: true), let app = Self.frontApp,
              let field = ScreenButtons.focusedField(box, bundleID: app) else { return false }
        if let suggestion = field.suggestion {
            // A newline would send half of it.
            type(suggestion.replacingOccurrences(of: "\n", with: " "))
            // Give the app a moment to take the text in before Return sends it.
            usleep(60000)
            log("complete:\(box): typed the suggestion shown in the box (\(suggestion.count) characters)")
            return false
        }
        guard field.hidesHint else {
            if field.isEmpty, let hint = field.placeholder {
                let shown = Self.stockHints.contains(hint) ? "\"\(hint)\"" : "of \(hint.count) characters"
                log("complete:\(box): no suggestion, the box shows its hint \(shown)")
            }
            return false
        }
        // The Claude app takes its hint away while a suggestion stands in its place, and keeps the
        // suggestion's text where accessibility cannot read it. Tab takes it, as by hand.
        post(Self.tab, down: true)
        post(Self.tab, down: false)
        usleep(120_000)
        guard let after = ScreenButtons.focusedField(box, bundleID: app) else {
            // Tab moved the focus out of the box: there was nothing to take. Put it back, and
            // keep the Return from pressing whatever has the focus now.
            post(KeyCombo(code: Self.tab.code, shift: true), down: true)
            post(KeyCombo(code: Self.tab.code, shift: true), down: false)
            log("complete:\(box): Tab found no suggestion and left the box; the focus is back")
            return true
        }
        if after.isEmpty {
            if after.text != field.text {
                // Tab typed blank space instead: take it out, and send nothing.
                post(KeyCombo(code: 51), down: true)
                post(KeyCombo(code: 51), down: false)
                log("complete:\(box): Tab typed blank space, taken out again")
                return true
            }
            log("complete:\(box): Tab found no suggestion")
            return false
        }
        log("complete:\(box): took the suggestion with Tab (\(after.text.trimmingCharacters(in: .whitespacesAndNewlines).count) characters)")
        return false
    }

    private static let tab = KeyCombo(code: 48)

    /// The Claude app's own grey hints in an empty box. Anything else might be a suggestion,
    /// so the log gives only its length.
    private static let stockHints: Set<String> = [
        "Type / for commands", "⌘⏎ to queue", "Describe a task or ask a question", "Describe something to build, change, or fix",
    ]

    // MARK: Typing

    private func mayType(checkApp: Bool) -> Bool {
        guard Accessibility.granted else {
            if !warnedAccess {
                warnedAccess = true
                log("cannot type keys: allow MicroBridge under Privacy & Security > Accessibility")
            }
            return false
        }
        warnedAccess = false
        guard checkApp, !keystrokeApps.isEmpty else { return true }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        if keystrokeApps.contains(front) { return true }
        log("not typing: \(front) is in front and is not in keystrokeApps")
        return false
    }

    /// Presses a key and keeps it down the way a keyboard does: after a short delay it repeats.
    /// A terminal only learns that a key is held from those repeats.
    private func hold(_ combo: KeyCombo) {
        held.removeValue(forKey: combo.code)?.invalidate()
        post(combo, down: true)
        let started = Date()
        held[combo.code] = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let age = Date().timeIntervalSince(started)
                if age > 120 {
                    // The release never came; do not leave the key down for good.
                    self.release(combo)
                } else if age >= 0.4 {
                    self.post(combo, down: true, repeating: true)
                }
            }
        }
    }

    private func release(_ combo: KeyCombo) {
        held.removeValue(forKey: combo.code)?.invalidate()
        post(combo, down: false)
    }

    private func post(_ combo: KeyCombo, down: Bool, repeating: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.code, keyDown: down) else { return }
        if repeating { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.shift { flags.insert(.maskShift) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func type(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let units = Array(line.utf16)
            // One event carries at most a short run of characters.
            for start in stride(from: 0, to: units.count, by: 16) {
                let chunk = Array(units[start ..< min(start + 16, units.count)])
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                    event.flags = []
                    event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event.post(tap: .cghidEventTap)
                }
                usleep(4000)
            }
            if index < lines.count - 1 {
                // Give the app a moment to take the text in before Return submits it.
                usleep(60000)
                post(KeyCombo(code: 36), down: true)
                post(KeyCombo(code: 36), down: false)
            }
        }
    }

    // MARK: Commands

    private func spawn(_ tool: String, _ arguments: [String], slot: Int?, session: Session?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // launchd starts the daemon with a bare PATH; add where developer tools usually live.
        let home = NSHomeDirectory()
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        if let slot { environment["MICRO_SLOT"] = String(slot) }
        if let session {
            environment["MICRO_SESSION"] = session.id
            environment["MICRO_STATUS"] = session.status.rawValue
            if let cwd = session.cwd { environment["MICRO_CWD"] = cwd }
            if let pid = session.pid { environment["MICRO_PID"] = String(pid) }
            if let host = session.host { environment["MICRO_HOST"] = host.description }
        }
        process.environment = environment
        var directory = home
        if let cwd = session?.cwd, FileManager.default.fileExists(atPath: cwd) { directory = cwd }
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log("could not run \(tool): \(error.localizedDescription)")
        }
    }

    /// Shows one session: its Code session in the Claude app. A session that did not say
    /// where it lives gets its app brought to the front.
    private func jump(to session: Session?) {
        switch session?.host {
        case let .claudeDesktop(id):
            // The app's own link for continuing one Code session; it also raises the window.
            spawn("/usr/bin/open", ["-b", "com.anthropic.claudefordesktop", "claude://code/continue?session=\(id)"],
                  slot: nil, session: nil)
        case nil:
            focus(session)
        }
    }

    /// Brings the app a session runs inside to the front: the nearest ancestor of the session's
    /// process that is a regular app (a terminal, an editor, Claude).
    private func focus(_ session: Session?) {
        guard let pid = session?.pid else {
            log("focus: this key has no session with a known process")
            return
        }
        var current = pid_t(pid)
        for _ in 0 ..< 16 where current > 1 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular,
               let bundle = app.bundleURL {
                spawn("/usr/bin/open", ["-a", bundle.path], slot: nil, session: nil)
                return
            }
            guard let parent = ProcessTree.parent(of: current) else { break }
            current = parent
        }
        log("focus: found no app around process \(pid)")
    }
}
