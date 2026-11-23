import AppKit
import ApplicationServices

/// Which button on screen a `click:` action presses, written `<box>/<pick>`.
///
///     click:Suggested next actions/first      the first button of the box with that label
///     click:Suggested next actions^2/Dismiss  the Dismiss button in that box, or in one of the
///                                             two containers around it, nearest first
///     click:epitaxy-approval-card/Deny        the Deny button of a box whose id or one of whose
///                                             classes is "epitaxy-approval-card"
///     click:*/Allow once                      the button labelled "Allow once", anywhere
///     click:epitaxy-approval-card/=Next!      the button labelled exactly "Next", so not "Show next
///                                             question"; `!` presses again while nothing has moved
public struct ButtonRule: Sendable, Equatable {
    public enum Pick: Sendable, Equatable {
        case first
        case last
        case number(Int)
        case label(String)
        /// A label that must be the button's whole text, written `=Label`.
        case exactly(String)
    }

    /// The box is the element whose label, id or one of whose classes is this text.
    /// Empty: the whole window.
    public var box: String
    /// How many containers around the box to try as well, when the box lacks the button.
    public var reach: Int
    public var pick: Pick
    /// Written as `!` after the pick. The button is one that goes away when it works, such as a
    /// card's "Submit", or whose box then says something else, such as a card's "Next": if it
    /// is still there holding the keyboard focus and its box says the same, it is pressed again.
    public var insist: Bool

    public init(box: String, reach: Int = 0, pick: Pick, insist: Bool = false) {
        self.box = box
        self.reach = reach
        self.pick = pick
        self.insist = insist
    }

    public static func parse(_ text: String) -> ButtonRule? {
        guard let slash = text.firstIndex(of: "/") else { return nil }
        var box = text[..<slash].trimmingCharacters(in: .whitespaces)
        var which = text[text.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        let insist = which.hasSuffix("!")
        if insist { which = String(which.dropLast()).trimmingCharacters(in: .whitespaces) }
        var reach = 0
        if let caret = box.lastIndex(of: "^") {
            guard let levels = Int(box[box.index(after: caret)...]), (1 ... 6).contains(levels) else { return nil }
            reach = levels
            box = box[..<caret].trimmingCharacters(in: .whitespaces)
        }
        guard !box.isEmpty, !which.isEmpty, box != "*" || reach == 0 else { return nil }
        let pick: Pick
        switch which.lowercased() {
        case "first": pick = .first
        case "last": pick = .last
        default:
            if let number = Int(which) {
                guard number >= 1 else { return nil }
                pick = .number(number)
            } else if which.hasPrefix("=") {
                let label = which.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !label.isEmpty else { return nil }
                pick = .exactly(label)
            } else {
                pick = .label(which)
            }
        }
        return ButtonRule(box: box == "*" ? "" : box, reach: reach, pick: pick, insist: insist)
    }

    public var spelling: String {
        let which = switch pick {
        case .first: "first"
        case .last: "last"
        case let .number(number): String(number)
        case let .label(label): label
        case let .exactly(label): "=" + label
        }
        return "\(box.isEmpty ? "*" : box)\(reach > 0 ? "^\(reach)" : "")/\(which)\(insist ? "!" : "")"
    }

    /// True when an element with this id, label and class list is the box the rule names.
    /// Each must be the whole text. A chat that mentions the text must not become a box, and
    /// neither must an element whose class only refers to the box, such as
    /// `has-[.epitaxy-approval-card]:shrink`.
    public func isBox(id: String?, label: String?, classes: [String]) -> Bool {
        guard !box.isEmpty else { return true }
        let needle = box.lowercased()
        return ([label ?? "", id ?? ""] + classes).contains { $0.lowercased() == needle }
    }

    /// Which of the box's buttons to press, given their labels in screen order.
    public func choose(from labels: [String]) -> Int? {
        switch pick {
        case .first: return labels.isEmpty ? nil : 0
        case .last: return labels.isEmpty ? nil : labels.count - 1
        case let .number(number): return number <= labels.count ? number - 1 : nil
        case let .label(wanted):
            let needle = wanted.lowercased()
            let lowered = labels.map { $0.lowercased() }
            return lowered.firstIndex(of: needle) ?? lowered.firstIndex { $0.contains(needle) }
        case let .exactly(wanted):
            return labels.firstIndex { $0.lowercased() == wanted.lowercased() }
        }
    }
}

/// Which option a `choose:` action turns on, written `<box>/<option class>/<next or prev>`.
///
///     choose:epitaxy-approval-card/epitaxy-answer-option/next
///
/// Inside the box, the options are the toggles (checkboxes, radio buttons) with that class.
/// `next` turns on the one after the option that is on, `prev` the one before it.
///
/// A box that takes several answers works differently, because turning an answer on there is
/// the answer itself. `next` and `prev` only move the keyboard focus, the highlight, from one
/// option to the next, and `mark` types Space on whatever is highlighted:
///
///     choose:epitaxy-approval-card/epitaxy-answer-option+Submit/next
///     choose:epitaxy-approval-card/epitaxy-answer-option/mark
///
/// `+Submit` names a button that comes after the last option, so the highlight can reach it.
/// `+Next|Submit` names two: whichever of them the box has.
///
/// An option is a toggle with the class, or a toggle inside a container with the class. The
/// second kind is a card's free-text answer, "Other".
public struct OptionRule: Sendable, Equatable {
    public enum Step: String, Sendable {
        case next
        case prev
        /// Press the highlighted option, in a box that takes several answers.
        case mark
    }

    /// The box, named as in a `click:` rule: its label, id or one of its classes.
    public var box: String
    /// The class every option carries.
    public var option: String
    /// The label of a button that comes after the last option, for the highlight to reach.
    public var then: String?
    public var step: Step

    public init(box: String, option: String, then: String? = nil, step: Step) {
        self.box = box
        self.option = option
        self.then = then
        self.step = step
    }

    public static func parse(_ text: String) -> OptionRule? {
        guard let first = text.firstIndex(of: "/"), let last = text.lastIndex(of: "/"), first < last else { return nil }
        let box = text[..<first].trimmingCharacters(in: .whitespaces)
        var option = text[text.index(after: first) ..< last].trimmingCharacters(in: .whitespaces)
        let way = text[text.index(after: last)...].trimmingCharacters(in: .whitespaces).lowercased()
        var then: String?
        if let plus = option.lastIndex(of: "+") {
            let label = option[option.index(after: plus)...].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { return nil }
            then = label
            option = option[..<plus].trimmingCharacters(in: .whitespaces)
        }
        guard !box.isEmpty, box != "*", !option.isEmpty, let step = Step(rawValue: way) else { return nil }
        return OptionRule(box: box, option: option, then: then, step: step)
    }

    public var spelling: String { "\(box)/\(option)\(then.map { "+" + $0 } ?? "")/\(step.rawValue)" }

    /// The labels `then` names, in lower case.
    public var thens: [String] {
        (then ?? "").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Which option to turn on, given which are on now, top to bottom. Nil: stay where it is.
    /// The ends do not wrap, so turning on past the last option keeps the last.
    ///
    /// `assuming` names the option the caller turned on a moment ago. An app takes a moment to
    /// show a press, so a fast second step would otherwise start from the old option again.
    public static func target(on: [Bool], step: Step, assuming recent: Int? = nil) -> Int? {
        guard !on.isEmpty, step != .mark else { return nil }
        let shown = recent.flatMap { on.indices.contains($0) ? $0 : nil } ?? on.lastIndex(of: true)
        guard let current = shown else { return step == .next ? 0 : on.count - 1 }
        let wanted = step == .next ? min(current + 1, on.count - 1) : max(current - 1, 0)
        return wanted == current ? nil : wanted
    }

    /// Where the highlight goes in a box that takes several answers. `stops` are the places it
    /// may rest on, counted top to bottom among everything in the box that can take the
    /// keyboard focus; `lit` is the place that has the focus now. Nil: stay. With the focus
    /// outside the box, it starts at the top.
    public static func stop(_ stops: [Int], from lit: Int?, step: Step) -> Int? {
        guard step != .mark else { return nil }
        guard let lit else { return stops.first }
        return step == .next ? stops.first { $0 > lit } : stops.last { $0 < lit }
    }
}

/// A button on screen in another app, found through the macOS accessibility tree.
public struct ScreenButton {
    /// What the button says: its title, else its description, else its value.
    public let label: String
    public let role: String
    /// The web page's `id` for the element, when the app is a web view.
    public let domID: String?
    /// The web page's class names for the element.
    public let classes: [String]
    public let enabled: Bool
    /// Screen position, top-left origin.
    public let frame: CGRect?
    /// Labels and class names of the containers around it, innermost first. Says which box it sits in.
    public let around: [String]

    let element: AXUIElement

    /// Clicks it. True when the app accepted the click.
    @discardableResult
    public func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Clicks a button that goes away when it works, and clicks it again while it does not.
    /// Returns how many clicks it took; 0 when the app refused the first.
    ///
    /// Seen in the Claude app on 2026-11-12: while the keyboard focus is outside a multiple-choice
    /// card, a press on its "Submit" only moves the focus onto the button. So for up to a second,
    /// every quarter second, a button that is still there, usable and holding the focus is
    /// pressed again. One that is gone, switched off or without the focus is left alone.
    ///
    /// Seen on 2026-11-18: a card with several questions has "Next", which stays while the card
    /// moves on to its next question. `box` is the card: once its title, the question, has
    /// changed, the press has worked and no more follow.
    public func pressUntilGone(in box: AXUIElement? = nil) -> Int {
        let said = box.flatMap(Self.title)
        guard press() else { return 0 }
        var presses = 1
        let started = Date()
        var pressed = started
        while Date().timeIntervalSince(started) < 1 {
            usleep(20000)
            guard flag(kAXEnabledAttribute) == true else { return presses }
            if let box, Self.title(box) != said { return presses }
            if flag(kAXFocusedAttribute) == true, Date().timeIntervalSince(pressed) >= 0.25 {
                _ = press()
                presses += 1
                pressed = Date()
            }
        }
        return presses
    }

    private static func title(_ element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// A yes-or-no fact about the button now. Nil when it is gone.
    private func flag(_ attribute: String) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}

/// Reads the buttons of another app's front window. Needs the same Accessibility permission
/// as typing keys does.
public enum ScreenButtons {
    public static var allowed: Bool { AXIsProcessTrusted() }

    public struct Listing {
        public var buttons: [ScreenButton] = []
        /// Elements looked at, and how long it took.
        public var nodes = 0
        public var seconds = 0.0
        /// Why the list is empty, when it is.
        public var problem: String?
    }

    public struct Found {
        /// The button the rule picked, when there is one.
        public var button: ScreenButton?
        /// Whether the rule's box is on screen, and how many usable buttons were looked through.
        public var boxShowing = false
        public var candidates = 0
        /// What those buttons say, in screen order.
        public var labels: [String] = []
        /// The box the button was found in.
        public var box: AXUIElement?
        public var nodes = 0
        public var seconds = 0.0
        public var problem: String?
    }

    /// Every button in the focused window of the running app with this bundle id, in the order
    /// the app lists them (top to bottom for a web view). `detail` records every container
    /// around each button, for working out what a rule can name.
    public static func list(bundleID: String, detail: Bool = false, maxNodes: Int = 30000,
                            maxSeconds: Double = 4) -> Listing {
        var listing = Listing()
        let started = Date()
        let window: Window
        switch open(bundleID) {
        case let .success(opened): window = opened
        case let .failure(problem):
            listing.problem = problem.text
            return listing
        }
        var pass = Pass(detail: detail, maxNodes: maxNodes, deadline: started.addingTimeInterval(maxSeconds))
        // The tree fills in a moment after it is first switched on: look again while it is bare.
        var attempts = 5
        while attempts > 0 {
            attempts -= 1
            pass.found = []
            pass.nodes = 0
            collect(window.root, around: [], pass: &pass)
            if pass.nodes > bareTree { break }
            if attempts > 0 { Thread.sleep(forTimeInterval: 0.4) }
        }
        listing.buttons = pass.found
        listing.nodes = pass.nodes
        listing.seconds = Date().timeIntervalSince(started)
        if listing.buttons.isEmpty { listing.problem = "no buttons found in \(listing.nodes) elements" }
        return listing
    }

    /// The button a rule picks in the focused window of the running app with this bundle id.
    /// When several boxes match, the last one counts: a web view puts the newest at the bottom.
    public static func find(_ rule: ButtonRule, bundleID: String, maxSeconds: Double = 3) -> Found {
        var found = Found()
        let started = Date()
        let window: Window
        switch open(bundleID) {
        case let .success(opened): window = opened
        case let .failure(problem):
            found.problem = problem.text
            return found
        }
        var pass = Pass(detail: false, maxNodes: 30000, deadline: started.addingTimeInterval(maxSeconds))
        // The box, then each container around it, innermost first.
        var path: [AXUIElement] = [window.root]
        if !rule.box.isEmpty {
            var attempts = 5
            while attempts > 0 {
                attempts -= 1
                path = []
                let looked = pass.nodes
                if locate(window.root, rule: rule, path: &path, pass: &pass) { break }
                if pass.nodes - looked > bareTree { break }
                if attempts > 0 { Thread.sleep(forTimeInterval: 0.4) }
            }
        }
        found.nodes = pass.nodes
        found.seconds = Date().timeIntervalSince(started)
        guard !path.isEmpty else { return found }
        found.boxShowing = true
        for container in path.prefix(rule.reach + 1) {
            pass.found = []
            collect(container, around: [], pass: &pass)
            let usable = pass.found.filter(\.enabled)
            found.candidates = usable.count
            found.labels = usable.map(\.label)
            found.nodes = pass.nodes
            if let index = rule.choose(from: found.labels) {
                found.button = usable[index]
                found.box = path.first
                break
            }
        }
        found.seconds = Date().timeIntervalSince(started)
        return found
    }

    public struct Chosen {
        public var options = 0
        /// The label of the option this call turned on, when it moved.
        public var pressed: String?
        /// The option that is on after this call, counted from 0, as far as this call knows.
        public var index: Int?
        /// How many presses the option took. More than one: the keyboard focus was elsewhere.
        public var presses = 0
        /// False when the option was pressed and the app still does not show it on.
        public var took = true
    }

    /// A box of options on screen, such as a multiple-choice card.
    public struct Card {
        public struct Place {
            public let label: String
            public let on: Bool
            /// True when it has the keyboard focus. For "Other", also while its text field has it.
            public fileprivate(set) var focused: Bool
            /// True for an option: a toggle that carries the rule's class, or sits in a container that does.
            public let isOption: Bool
            /// True for the option that only its container marks: the card's free-text answer, "Other".
            public let isOther: Bool
            /// True for the button the rule names after the options.
            public let isThen: Bool
            let element: AXUIElement
        }

        public let box: AXUIElement
        /// Every usable toggle and button in the box, top to bottom.
        public let places: [Place]
        /// True when the box takes several answers.
        public let many: Bool
        /// What the free-text answer's field holds, while that field has the keyboard focus.
        public let fieldText: String?

        public var options: [Place] { places.filter(\.isOption) }
        /// The place that has the keyboard focus.
        public var lit: Int? { places.firstIndex(where: \.focused) }
        /// The places a highlight may rest on: the options, then the button named after them.
        public var stops: [Int] { places.indices.filter { places[$0].isOption || places[$0].isThen } }

        /// Moves the keyboard focus onto a place.
        public func focus(_ index: Int) -> Bool {
            places.indices.contains(index)
                && AXUIElementSetAttributeValue(places[index].element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
        }

        /// True once the app says the place has the keyboard focus. Waits up to a quarter second.
        public func focusLanded(on index: Int) -> Bool {
            guard places.indices.contains(index) else { return false }
            let started = Date()
            repeat {
                var value: AnyObject?
                if AXUIElementCopyAttributeValue(places[index].element, kAXFocusedAttribute as CFString, &value) == .success,
                   (value as? Bool) == true {
                    return true
                }
                usleep(15000)
            } while Date().timeIntervalSince(started) < 0.25
            return false
        }
    }

    public struct Looked {
        public var card: Card?
        /// False when the box itself is not on screen.
        public var boxShowing = false
        public var nodes = 0
        public var seconds = 0.0
        public var problem: String?
    }

    /// Finds the box a rule names in the focused window of the running app, with its options.
    /// `known` is the box a call just before this one found: looking inside it alone takes a few
    /// milliseconds, where searching the window takes a tenth of a second and slows the app down.
    public static func card(_ rule: OptionRule, bundleID: String, in known: AXUIElement? = nil, maxSeconds: Double = 3) -> Looked {
        var looked = Looked()
        let started = Date()
        var pass = Pass(detail: false, maxNodes: 30000, deadline: started.addingTimeInterval(maxSeconds))
        let option = rule.option.lowercased()
        let then = rule.thens
        var found = Gathered()
        var box: AXUIElement?
        if let known {
            gather(known, option: option, then: then, into: &found, pass: &pass)
            if found.places.contains(where: \.isOption) { box = known }
        }
        if box == nil {
            // No box handed over, or it is gone or answered: search the window.
            found = Gathered()
            switch open(bundleID) {
            case let .success(window):
                var path: [AXUIElement] = []
                if locate(window.root, rule: ButtonRule(box: rule.box, pick: .first), path: &path, pass: &pass) {
                    looked.boxShowing = true
                    gather(path[0], option: option, then: then, into: &found, pass: &pass)
                    if found.places.contains(where: \.isOption) { box = path[0] }
                }
            case let .failure(problem):
                looked.problem = problem.text
            }
        }
        if let box {
            looked.boxShowing = true
            var places = found.places
            // Typing the free-text answer counts as resting on "Other": the highlight goes on from there.
            if found.fieldText != nil, !places.contains(where: \.focused), let other = places.firstIndex(where: \.isOther) {
                places[other].focused = true
            }
            looked.card = Card(box: box, places: places, many: found.many, fieldText: found.fieldText)
        }
        looked.nodes = pass.nodes
        looked.seconds = Date().timeIntervalSince(started)
        return looked
    }

    /// In a card that takes one answer: turns on the option after or before the one that is on.
    /// `assuming` is the option the caller turned on a moment ago, in case the app does not show it yet.
    public static func choose(in card: Card, step: OptionRule.Step, assuming recent: Int? = nil) -> Chosen {
        var chosen = Chosen()
        let options = card.options
        chosen.options = options.count
        let shown = options.map(\.on)
        chosen.index = recent.flatMap { shown.indices.contains($0) ? $0 : nil } ?? shown.lastIndex(of: true)
        if let index = OptionRule.target(on: shown, step: step, assuming: recent),
           AXUIElementPerformAction(options[index].element, kAXPressAction as CFString) == .success {
            chosen.pressed = options[index].label
            chosen.index = index
            chosen.presses = 1
            if !options.contains(where: \.focused) {
                (chosen.presses, chosen.took) = insist(on: options[index].element)
            }
        }
        return chosen
    }

    /// Presses an option again, every quarter second for up to a second, until the app shows it on.
    ///
    /// Seen in the Claude app on 2026-11-12: while the keyboard focus is outside a card's options,
    /// a press on an option only moves the focus onto it. A press half a second later turns it on.
    /// The caller has pressed once already.
    private static func insist(on element: AXUIElement) -> (presses: Int, took: Bool) {
        var presses = 1
        let started = Date()
        var pressed = started
        while Date().timeIntervalSince(started) < 1 {
            usleep(20000)
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
               (value as? NSNumber)?.intValue == 1 {
                return (presses, true)
            }
            if Date().timeIntervalSince(pressed) >= 0.25 {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                presses += 1
                pressed = Date()
            }
        }
        return (presses, false)
    }

    private struct Gathered {
        var places: [Card.Place] = []
        var many = false
        var fieldText: String?
    }

    private static let placeFacts = [
        kAXRoleAttribute, kAXChildrenAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
        kAXEnabledAttribute, "AXDOMClassList", kAXFocusedAttribute, kAXSubroleAttribute,
    ]

    /// Gathers, top to bottom, every usable toggle and button under an element, and notes
    /// whether the box counts its answers.
    private static func gather(_ element: AXUIElement, option: String, then: [String], inside: Bool = false,
                               into found: inout Gathered, pass: inout Pass) {
        guard pass.mayVisit() else { return }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, placeFacts as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == placeFacts.count else { return }
        let role = values[0] as? String ?? ""
        let usable = (values[5] as? Bool) ?? true
        let label = [values[2] as? String, values[3] as? String].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        let focused = (values[7] as? Bool) ?? false
        let carries = (values[6] as? [String] ?? []).contains { $0.lowercased() == option }
        if role == kAXCheckBoxRole || role == kAXRadioButtonRole {
            guard usable else { return }
            found.places.append(Card.Place(
                label: label, on: (values[4] as? NSNumber)?.intValue == 1, focused: focused,
                isOption: carries || inside, isOther: inside && !carries, isThen: false, element: element
            ))
            return
        }
        if role == kAXButtonRole {
            guard usable else { return }
            let isThen = then.contains(label.lowercased()) && !found.places.contains(where: \.isThen)
            found.places.append(Card.Place(label: label, on: false, focused: focused, isOption: false, isOther: false,
                                           isThen: isThen, element: element))
            return
        }
        if role == kAXTextAreaRole || role == kAXTextFieldRole {
            // Seen in the Claude app on 2026-11-18: turning "Other" on puts a text field beside it,
            // in the same container, and gives that field the keyboard focus.
            if inside, focused { found.fieldText = values[4] as? String ?? "" }
            return
        }
        let children = values[1] as? [AnyObject] ?? []
        if (values[8] as? String) == "AXApplicationStatus" {
            // Seen in the Claude app on 2026-11-12: a card that takes several answers keeps a
            // counter here for screen readers ("2 selected"). A card that takes one leaves it empty.
            for child in children {
                var text: AnyObject?
                if AXUIElementCopyAttributeValue(child as! AXUIElement, kAXValueAttribute as CFString, &text) == .success,
                   let text = text as? String, !text.isEmpty {
                    found.many = true
                }
            }
            return
        }
        for child in children {
            gather(child as! AXUIElement, option: option, then: then, inside: inside || carries, into: &found, pass: &pass)
        }
    }

    /// Everything inside a rule's box, one line per element, indented by depth: role, texts,
    /// whether it has the keyboard focus or is selected, and what can be done to it. For working
    /// out what a key could press or focus. Nil when the box is not on screen.
    public static func tree(of rule: ButtonRule, bundleID: String, maxSeconds: Double = 3) -> [String]? {
        guard case let .success(window) = open(bundleID) else { return nil }
        var pass = Pass(detail: true, maxNodes: 30000, deadline: Date().addingTimeInterval(maxSeconds))
        var path: [AXUIElement] = [window.root]
        if !rule.box.isEmpty {
            path = []
            guard locate(window.root, rule: rule, path: &path, pass: &pass) else { return nil }
        }
        var lines: [String] = []
        describe(path[min(rule.reach, path.count - 1)], depth: 0, into: &lines, pass: &pass)
        return lines
    }

    /// A text field that has the keyboard focus: what is typed in it, and the grey hint it
    /// shows while it is empty (its placeholder).
    public struct Field: Sendable, Equatable {
        public let text: String
        public let placeholder: String?
        /// Grey text the app draws inside the box as a suggestion (ghost text), when it shows some.
        public let ghost: String?

        public init(text: String, placeholder: String?, ghost: String? = nil) {
            self.text = text
            self.placeholder = placeholder
            self.ghost = ghost
        }

        /// The suggestion to send: ghost text in a box that holds nothing typed. Some boxes count
        /// their ghost text in their value, so a value that is just the ghost counts as empty.
        public var suggestion: String? {
            guard let ghost = ghost?.trimmingCharacters(in: .whitespacesAndNewlines), !ghost.isEmpty else { return nil }
            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return typed.isEmpty || typed == ghost ? ghost : nil
        }

        /// True when nothing but blank space is typed.
        public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        /// True when the box is empty and shows no hint and no readable suggestion. The Claude
        /// app takes its hint away while a suggestion stands in its place.
        public var hidesHint: Bool { isEmpty && placeholder == nil && suggestion == nil }
    }

    /// The text field with the keyboard focus in the app, when its label, id or one of its
    /// classes is `box`. Nil when the focus is anywhere else. Asks for the focus directly, so
    /// it takes milliseconds, not a walk through the window.
    public static func focusedField(_ box: String, bundleID: String) -> Field? {
        guard allowed, let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focused as! AXUIElement
        let role = attribute(element, kAXRoleAttribute) as? String
        guard role == kAXTextAreaRole || role == kAXTextFieldRole else { return nil }
        let named = { (name: String) in (attribute(element, name) as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let rule = ButtonRule(box: box, pick: .first)
        guard rule.isBox(id: named("AXDOMIdentifier"), label: named(kAXTitleAttribute) ?? named(kAXDescriptionAttribute),
                         classes: attribute(element, "AXDOMClassList") as? [String] ?? [])
        else { return nil }
        return Field(text: attribute(element, kAXValueAttribute) as? String ?? "", placeholder: named(kAXPlaceholderValueAttribute),
                     ghost: ghostText(in: element))
    }

    /// The text of the first element inside `field`, a few levels down, whose class says it is
    /// ghost text or a suggestion.
    private static func ghostText(in field: AXUIElement) -> String? {
        var seen = 0
        func search(_ element: AXUIElement, level: Int) -> String? {
            for child in attribute(element, kAXChildrenAttribute) as? [AnyObject] ?? [] {
                seen += 1
                guard seen <= 60 else { return nil }
                let node = child as! AXUIElement
                let classes = attribute(node, "AXDOMClassList") as? [String] ?? []
                if classes.contains(where: { $0.lowercased().contains("ghost") || $0.lowercased().contains("suggestion") }) {
                    return text(of: node)
                }
                if level < 3, let found = search(node, level: level + 1) { return found }
            }
            return nil
        }
        return search(field, level: 1)
    }

    /// An element's own value, or the values of the text inside it joined up.
    private static func text(of element: AXUIElement) -> String? {
        if let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty { return value }
        let parts = (attribute(element, kAXChildrenAttribute) as? [AnyObject] ?? []).compactMap { child in
            attribute(child as! AXUIElement, kAXValueAttribute) as? String
        }
        let joined = parts.joined()
        return joined.isEmpty ? nil : joined
    }

    /// Every attribute of a box and of what is inside it, a few levels down, for finding where
    /// an app keeps something the tree does not print.
    public static func attributes(of rule: ButtonRule, bundleID: String, depth: Int = 3) -> [String]? {
        guard case let .success(window) = open(bundleID) else { return nil }
        var pass = Pass(detail: true, maxNodes: 30000, deadline: Date().addingTimeInterval(3))
        var path: [AXUIElement] = []
        guard locate(window.root, rule: rule, path: &path, pass: &pass) else { return nil }
        var lines: [String] = []
        func dump(_ element: AXUIElement, level: Int) {
            guard lines.count < 600 else { return }
            let indent = String(repeating: "  ", count: level)
            var names: CFArray?
            guard AXUIElementCopyAttributeNames(element, &names) == .success, let all = names as? [String] else { return }
            lines.append(indent + "---")
            for name in all.sorted() where name != kAXChildrenAttribute && name != kAXParentAttribute {
                guard let value = attribute(element, name) else { continue }
                let shown: String = switch value {
                case let string as String: "\"" + string.prefix(80).replacingOccurrences(of: "\n", with: "\\n") + "\""
                case let number as NSNumber: number.stringValue
                case let list as [AnyObject]: "[\(list.count) items]"
                default: String(describing: type(of: value))
                }
                lines.append(indent + name + " = " + shown)
            }
            guard level < depth else { return }
            for child in attribute(element, kAXChildrenAttribute) as? [AnyObject] ?? [] {
                dump(child as! AXUIElement, level: level + 1)
            }
        }
        dump(path[min(rule.reach, path.count - 1)], level: 0)
        return lines
    }

    private static let treeFacts = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXChildrenAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        kAXValueAttribute, kAXFocusedAttribute, kAXEnabledAttribute, "AXDOMIdentifier", "AXDOMClassList",
        kAXSelectedAttribute,
    ]

    private static func describe(_ element: AXUIElement, depth: Int, into lines: inout [String], pass: inout Pass) {
        guard pass.mayVisit(), lines.count < 400 else { return }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, treeFacts as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == treeFacts.count else { return }
        func text(_ index: Int) -> String? {
            guard let string = values[index] as? String, !string.isEmpty else { return nil }
            return string
        }
        var parts = [text(0) ?? "?"]
        if let subrole = text(1) { parts.append("(\(subrole))") }
        if let title = text(3) { parts.append("title=\"\(title.prefix(50))\"") }
        if let description = text(4) { parts.append("desc=\"\(description.prefix(50))\"") }
        if let value = text(5) {
            parts.append("value=\"\(value.prefix(50))\"")
        } else if let number = values[5] as? NSNumber {
            parts.append("value=\(number)")
        }
        if parts[0] == "AXWebArea", let url = attribute(element, "AXURL") as? URL { parts.append("url=\(url.absoluteString)") }
        if (values[6] as? Bool) == true { parts.append("FOCUSED") }
        if (values[10] as? Bool) == true { parts.append("SELECTED") }
        if (values[7] as? Bool) == false { parts.append("off") }
        if let id = text(8) { parts.append("#\(id)") }
        if let classes = values[9] as? [String], !classes.isEmpty { parts.append("." + classes.prefix(3).joined(separator: ".")) }
        var names: CFArray?
        if AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String], !actions.isEmpty {
            parts.append("[" + actions.map { $0.replacingOccurrences(of: "AX", with: "") }.joined(separator: ",") + "]")
        }
        lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
        for child in values[2] as? [AnyObject] ?? [] {
            describe(child as! AXUIElement, depth: depth + 1, into: &lines, pass: &pass)
        }
    }

    // MARK: Panes

    /// The parts of an app's front window that scroll on their own, in screen points from the
    /// top left and cut to the window: a native scroll area, a web page inside the window, or a
    /// web element made to scroll. Smaller than `smallestPane` either way, it does not count.
    public static func panes(bundleID: String, maxSeconds: Double = 0.5) -> [CGRect] {
        layout(bundleID: bundleID, box: nil, maxSeconds: maxSeconds).panes
    }

    /// The panes of an app's front window, as `panes` finds them, and where the text box named
    /// `box` (its label, id or one of its classes) is, when the walk passes one.
    public static func layout(bundleID: String, box: String?, maxSeconds: Double = 0.5) -> (panes: [CGRect], box: CGRect?) {
        guard case let .success(window) = open(bundleID),
              let whole = rect(attribute(window.root, kAXPositionAttribute), attribute(window.root, kAXSizeAttribute))
        else { return ([], nil) }
        var pass = Pass(detail: false, maxNodes: 5000, deadline: Date().addingTimeInterval(maxSeconds))
        var walk = PaneWalk(window: whole, box: box.map { ButtonRule(box: $0, pick: .first) })
        gatherPanes(window.root, pass: &pass, into: &walk)
        return (walk.found, walk.boxFrame)
    }

    /// For `micro panes`: what each pane is, as its role, id and classes.
    public static func paneNames(bundleID: String) -> [(CGRect, String)] {
        guard case let .success(window) = open(bundleID),
              let whole = rect(attribute(window.root, kAXPositionAttribute), attribute(window.root, kAXSizeAttribute))
        else { return [] }
        var pass = Pass(detail: false, maxNodes: 5000, deadline: Date().addingTimeInterval(0.5))
        var walk = PaneWalk(window: whole, box: nil)
        gatherPanes(window.root, pass: &pass, into: &walk)
        return Array(zip(walk.found, walk.names))
    }

    private struct PaneWalk {
        let window: CGRect
        let box: ButtonRule?
        var found: [CGRect] = []
        var names: [String] = []
        var boxFrame: CGRect?
    }

    public static let smallestPane = 150.0

    private static let paneFacts = [kAXRoleAttribute, kAXChildrenAttribute, "AXDOMClassList", kAXPositionAttribute, kAXSizeAttribute,
                                    kAXTitleAttribute, kAXDescriptionAttribute, "AXDOMIdentifier"]
    /// The classes that make a web element scroll up and down, as Tailwind names them.
    private static let scrollClasses: Set<String> = ["overflow-y-auto", "overflow-auto", "overflow-y-scroll", "overflow-scroll"]

    /// Stops at each pane: what is inside one, such as a long chat, can be very large.
    private static func gatherPanes(_ element: AXUIElement, pass: inout Pass, into walk: inout PaneWalk) {
        guard pass.mayVisit() else { return }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, paneFacts as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == paneFacts.count else { return }
        let window = walk.window
        let frame = rect(values[3], values[4])?.intersection(window)
        let role = values[0] as? String ?? ""
        let classes = values[2] as? [String] ?? []
        if let box = walk.box, walk.boxFrame == nil, role == kAXTextAreaRole || role == kAXTextFieldRole {
            let named = { (index: Int) in (values[index] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            if box.isBox(id: named(7), label: named(5) ?? named(6), classes: classes) { walk.boxFrame = frame }
        }
        let scrolls = switch role {
        case kAXScrollAreaRole, "AXWebArea": true
        default: !scrollClasses.isDisjoint(with: classes)
        }
        // What fills the window is its frame, not a pane: an Electron app's whole window is one
        // web page in one scroll area, with its panes inside.
        let fills = frame.map { $0.width * $0.height >= window.width * window.height * 0.9 } ?? false
        // One too small to be a pane is walked into: the Claude app's message box is inside one.
        if scrolls, !fills, let frame, frame.width >= smallestPane, frame.height >= smallestPane {
            walk.found.append(frame)
            walk.names.append("\(role) id=\(values[7] as? String ?? "") classes=\(classes.joined(separator: " "))")
            return
        }
        for child in values[1] as? [AnyObject] ?? [] {
            gatherPanes(child as! AXUIElement, pass: &pass, into: &walk)
        }
    }

    private static func rect(_ position: AnyObject?, _ size: AnyObject?) -> CGRect? {
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    // MARK: The session on screen

    /// The sessions an app's windows show right now, read from the address of each web page in
    /// them. Empty when the app is not running, has no window, or shows something else.
    public static func shownSessions(bundleID: String) -> [SessionHost] {
        guard allowed, let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return []
        }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        // Electron apps build their web accessibility tree only when asked to.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var hosts: [SessionHost] = []
        var left = 200
        for window in attribute(app, kAXWindowsAttribute) as? [AnyObject] ?? [] {
            pages(in: window as! AXUIElement, depth: 0, left: &left, into: &hosts)
        }
        return hosts
    }

    /// Walks the window's frame down to its web pages and stops at each: a page's address is all
    /// that is wanted, and what is inside a page can be very large.
    private static func pages(in element: AXUIElement, depth: Int, left: inout Int, into hosts: inout [SessionHost]) {
        guard left > 0, depth < 14 else { return }
        left -= 1
        if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
            if let url = attribute(element, "AXURL") as? URL, let host = SessionHost(page: url), !hosts.contains(host) {
                hosts.append(host)
            }
            return
        }
        for child in attribute(element, kAXChildrenAttribute) as? [AnyObject] ?? [] {
            pages(in: child as! AXUIElement, depth: depth + 1, left: &left, into: &hosts)
        }
    }

    // MARK: Walking

    private struct Window {
        let root: AXUIElement
    }

    /// A window with no more elements than this has not built its web accessibility tree yet.
    private static let bareTree = 50

    private struct Problem: Error {
        let text: String
    }

    private struct Pass {
        let detail: Bool
        let maxNodes: Int
        let deadline: Date
        var found: [ScreenButton] = []
        var nodes = 0

        mutating func mayVisit() -> Bool {
            guard nodes < maxNodes, Date() < deadline else { return false }
            nodes += 1
            return true
        }
    }

    private static func open(_ bundleID: String) -> Result<Window, Problem> {
        guard allowed else {
            return .failure(Problem(text: "MicroBridge is not allowed under Privacy & Security > Accessibility"))
        }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return .failure(Problem(text: "\(bundleID) is not running"))
        }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 2)
        // Electron apps build their web accessibility tree only when asked to. The setting cannot
        // be read back, so ask every time.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window = (attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute)
            ?? (attribute(app, kAXWindowsAttribute) as? [AnyObject])?.first) else {
            return .failure(Problem(text: "\(bundleID) has no window"))
        }
        return .success(Window(root: window as! AXUIElement))
    }

    private static let boxFacts = [
        kAXRoleAttribute, kAXChildrenAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        "AXDOMIdentifier", "AXDOMClassList",
    ]

    /// Finds the rule's box, looking from the bottom of the window up. On success `path` holds
    /// the box, then each container around it up to the window.
    private static func locate(_ element: AXUIElement, rule: ButtonRule, path: inout [AXUIElement], pass: inout Pass) -> Bool {
        guard pass.mayVisit() else { return false }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, boxFacts as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == boxFacts.count else { return false }
        func text(_ index: Int) -> String? {
            guard let string = values[index] as? String, !string.isEmpty else { return nil }
            return string
        }
        let role = text(0) ?? ""
        // A box holds buttons; it is neither one itself nor a run of text.
        guard role != kAXButtonRole, role != kAXStaticTextRole else { return false }
        if rule.isBox(id: text(4), label: text(2) ?? text(3), classes: values[5] as? [String] ?? []) {
            path.append(element)
            return true
        }
        for child in (values[1] as? [AnyObject] ?? []).reversed() where locate(child as! AXUIElement, rule: rule, path: &path, pass: &pass) {
            path.append(element)
            return true
        }
        return false
    }

    private static let buttonFacts = [
        kAXRoleAttribute, kAXChildrenAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
        kAXEnabledAttribute, "AXDOMIdentifier", "AXDOMClassList", kAXPositionAttribute, kAXSizeAttribute,
    ]

    /// Gathers the buttons under an element, top to bottom.
    private static func collect(_ element: AXUIElement, around: [String], pass: inout Pass) {
        guard pass.mayVisit() else { return }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, buttonFacts as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
              let values = raw as? [AnyObject], values.count == buttonFacts.count else { return }
        func text(_ index: Int) -> String? {
            guard let string = values[index] as? String, !string.isEmpty else { return nil }
            return string
        }
        let role = text(0) ?? ""
        let children = values[1] as? [AnyObject] ?? []
        let label = text(2) ?? text(3) ?? text(4) ?? ""
        let classes = values[7] as? [String] ?? []
        if role == kAXButtonRole {
            var frame: CGRect?
            if CFGetTypeID(values[8]) == AXValueGetTypeID(), CFGetTypeID(values[9]) == AXValueGetTypeID() {
                var point = CGPoint.zero
                var size = CGSize.zero
                if AXValueGetValue(values[8] as! AXValue, .cgPoint, &point),
                   AXValueGetValue(values[9] as! AXValue, .cgSize, &size) {
                    frame = CGRect(origin: point, size: size)
                }
            }
            pass.found.append(ScreenButton(label: label.isEmpty ? buttonText(children) : label, role: role,
                                           domID: text(6), classes: classes, enabled: (values[5] as? Bool) ?? true,
                                           frame: frame, around: around, element: element))
            return
        }
        // Remember what this container is, for the buttons inside it.
        var inner = around
        let name = [text(6).map { "#\($0)" }, label.isEmpty ? nil : "\"\(label.prefix(60))\"",
                    classes.isEmpty ? nil : "." + classes.prefix(pass.detail ? 24 : 6).joined(separator: ".")]
            .compactMap { $0 }.joined(separator: " ")
        if !name.isEmpty || pass.detail {
            inner.insert(name.isEmpty ? role : "\(role) \(name)", at: 0)
            if inner.count > (pass.detail ? 14 : 6) { inner.removeLast() }
        }
        for child in children {
            collect(child as! AXUIElement, around: inner, pass: &pass)
        }
    }

    /// A button with no label of its own: the text inside it.
    private static func buttonText(_ children: [AnyObject], depth: Int = 0) -> String {
        guard depth < 4 else { return "" }
        var parts: [String] = []
        for child in children.prefix(12) {
            let element = child as! AXUIElement
            for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let string = attribute(element, name) as? String, !string.isEmpty {
                    parts.append(string)
                    break
                }
            }
            if parts.isEmpty, let inner = attribute(element, kAXChildrenAttribute) as? [AnyObject] {
                let text = buttonText(inner, depth: depth + 1)
                if !text.isEmpty { parts.append(text) }
            }
        }
        return parts.joined(separator: " ")
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
