import Foundation

extension KeyCombo {
    /// A key combination as a Mac shows it: "cmd+shift+m" becomes "⇧⌘M".
    public static func symbols(_ spelling: String) -> String {
        let named = [
            "return": "Return", "enter": "Return", "tab": "Tab", "space": "Space", "delete": "Delete",
            "backspace": "Delete", "forwarddelete": "Forward Delete", "escape": "Esc", "esc": "Esc",
            "home": "Home", "end": "End", "pageup": "Page Up", "pagedown": "Page Down",
            "left": "←", "right": "→", "up": "↑", "down": "↓",
        ]
        let parts = spelling.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last else { return spelling }
        var modifiers = ""
        // The order macOS menus use.
        for (names, symbol) in [(["ctrl", "control"], "⌃"), (["opt", "option", "alt"], "⌥"), (["shift"], "⇧"),
                                (["cmd", "command"], "⌘")] where parts.dropLast().contains(where: names.contains) {
            modifiers += symbol
        }
        let name = named[key] ?? key.uppercased()
        // A named key reads better apart from its modifiers: "⇧ Tab", but "⌘B".
        return modifiers.isEmpty || name.count == 1 ? modifiers + name : modifiers + " " + name
    }
}

extension Action {
    /// What the action does, in plain words, for people who do not read the config file's syntax.
    public var plainWords: String {
        switch self {
        case .none: return "Nothing"
        case .ack: return "Mark the session as read"
        case .jump: return "Show the session"
        case .focus: return "Bring the session's app to the front"
        case .forget: return "Forget the session and free the key"
        case .pin: return "Pin the session to its key, or unpin it"
        case .lock: return "Turn the lights off and lock the Mac"
        case let .scroll(up): return up ? "Scroll up" : "Scroll down"
        case let .pane(left): return "Move the pointer to the pane on the \(left ? "left" : "right")"
        case let .key(_, phase, spelling):
            let keys = KeyCombo.symbols(spelling)
            switch phase {
            case .tap: return "Type \(keys)"
            case .down: return "Hold down \(keys)"
            case .up: return "Let go of \(keys)"
            }
        case let .text(text):
            let sends = text.hasSuffix("\n")
            let shown = (sends ? String(text.dropLast()) : text).replacingOccurrences(of: "\n", with: " ")
            return "Type \"\(shown)\"" + (sends ? " and send it" : "")
        case let .shell(command): return "Run \(command)"
        case let .open(target): return "Open \(target)"
        case let .click(rule):
            let button = switch rule.pick {
            case .first: "the first button"
            case .last: "the last button"
            case let .number(place): "button \(place)"
            case let .label(label), let .exactly(label): "\"\(label)\""
            }
            return "Press \(button) " + (rule.box.isEmpty ? "anywhere in the window" : "in \(Self.boxName(rule.box))")
        case let .choose(rule):
            switch rule.step {
            case .next: return "Move to the next answer in \(Self.boxName(rule.box))"
            case .prev: return "Move to the previous answer in \(Self.boxName(rule.box))"
            case .mark: return "Tick the highlighted answer in \(Self.boxName(rule.box))"
            }
        case let .complete(box): return "Fill in the suggestion \(box == "Prompt" ? "the message box" : box) shows, if nothing is typed"
        case let .command(name, _): return "The \(name) command"
        }
    }

    /// The Claude app's card for a permission prompt or a question has a name nobody would
    /// guess. Any other box keeps the name the file gives it.
    private static func boxName(_ box: String) -> String {
        box == "epitaxy-approval-card" ? "the prompt card" : box
    }

    /// True for an action that ends its list when it finds its button or its options on screen.
    public var endsListWhenItWorks: Bool {
        switch self {
        case .click, .choose: true
        default: false
        }
    }
}
