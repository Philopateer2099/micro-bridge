import AppKit
import Foundation

/// One Claude chat as Orca lists it.
public struct OrcaChat: Sendable, Equatable {
    /// Orca's session ID. The chat keeps it across /clear.
    public var id: String
    /// What its tab says.
    public var title: String
    /// Orca's ID for the workspace it is open in, as `orca worktree activate --worktree id:…` takes it.
    public var worktree: String
    /// What Orca says it is doing.
    public var status: AgentStatus

    public init(id: String, title: String, worktree: String, status: AgentStatus) {
        self.id = id
        self.title = title
        self.worktree = worktree
        self.status = status
    }
}

/// One tab of the workspace on screen in Orca's window.
public struct OrcaTab: Sendable, Equatable {
    public var title: String
    /// The tab whose content the window shows.
    public var selected: Bool

    public init(title: String, selected: Bool) {
        self.title = title
        self.selected = selected
    }
}

/// What the bridge knows of Orca: how its command line answers and how its window names things.
/// Seen in Orca 1.4.271.
public enum Orca {
    public static let bundleID = "com.stablyai.orca"
    /// The class of the box that holds the tabs, and of the tab whose content shows.
    static let tabStrip = "group/tab-strip"
    static let selectedTab = "bg-tab-active"
    /// The words between a tab's title and its close button's name.
    private static let closeWords = " Close tab "

    public struct Problem: Error, Equatable, Sendable {
        public var text: String

        public init(_ text: String) { self.text = text }
    }

    /// Which chat a hold on an empty key takes.
    public enum Pick: Equatable, Sendable {
        case chat(OrcaChat)
        /// No chat, and why.
        case unclear(String)
    }

    /// Orca's word for what an agent is doing, as a key shows it. A chat that has done nothing
    /// yet has no word.
    static func status(_ state: String?) -> AgentStatus {
        switch state {
        case "working": .working
        case "blocked", "waiting": .needsYou
        case "done": .done
        default: .idle
        }
    }

    private static func chat(_ item: JSONValue) -> OrcaChat? {
        guard item["kind"]?.string == "chat", item["agent"]?.string == "claude",
              let id = item["orcaSessionId"]?.string, SessionHost("orca:" + id) != nil,
              let worktree = item["worktreeId"]?.string else { return nil }
        return OrcaChat(id: id, title: item["title"]?.string ?? "", worktree: worktree, status: status(item["state"]?.string))
    }

    private static func problem(in root: JSONValue?) -> Problem {
        Problem("Orca: " + (root?["error"]?["message"]?.string.map { String($0.prefix(200)) } ?? "its answer could not be read"))
    }

    /// The Claude chats in the answer of `orca agent list --json`. Terminal agents and other
    /// agents' chats are left out: only Claude's chats report to the bridge (D-053).
    public static func chats(fromList text: String) -> Result<[OrcaChat], Problem> {
        guard let root = JSONValue.parse(text), root["ok"]?.bool == true, case let .array(items)? = root["result"]?["agents"] else {
            return .failure(problem(in: JSONValue.parse(text)))
        }
        return .success(items.compactMap(chat))
    }

    /// Where a chat is open, from the answer of `orca agent show <id> --json`. Nil when Orca
    /// has no open tab for it: the chat was closed.
    public static func place(fromShow text: String) -> Result<OrcaChat?, Problem> {
        guard let root = JSONValue.parse(text) else { return .failure(problem(in: nil)) }
        if root["ok"]?.bool == true, case let .array(places)? = root["result"]?["places"] {
            return .success(places.compactMap(chat).first)
        }
        if root["error"]?["code"]?.string == "agent_unknown" { return .success(nil) }
        return .failure(problem(in: root))
    }

    /// A tab from its button. Its title is the text the button shows (`shown`). A button read
    /// without that says its state, its title, "Close tab" and the title again; a tab that
    /// cannot be closed, such as a bot's Home, has a label of its own and only the shown text
    /// names it. Nil for a button that is no tab.
    public static func tab(shown: String? = nil, label: String, classes: [String]) -> OrcaTab? {
        if let shown, !shown.isEmpty { return OrcaTab(title: shown, selected: classes.contains(selectedTab)) }
        var from = label.startIndex
        while let words = label.range(of: closeWords, range: from ..< label.endIndex) {
            let title = String(label[words.upperBound...])
            if !title.isEmpty, label[..<words.lowerBound].hasSuffix(title) {
                return OrcaTab(title: title, selected: classes.contains(selectedTab))
            }
            from = words.upperBound
        }
        return nil
    }

    /// The chat a hold on an empty key takes (D-043): the one whose tab shows; with another
    /// kind of tab showing, the only chat among the tabs of the workspace on screen. A split
    /// view shows a tab in each part.
    public static func pick(tabs: [OrcaTab], chats: [OrcaChat]) -> Pick {
        guard !tabs.isEmpty else { return .unclear("Orca's window shows no tabs") }
        let showing = Set(tabs.filter(\.selected).map(\.title))
        let named = chats.filter { showing.contains($0.title) }
        if named.count == 1 { return .chat(named[0]) }
        if named.count > 1 {
            return .unclear(Set(named.map(\.title)).count == 1 ? "\(named.count) chats have the title of the tab on screen"
                : "\(named.count) chats are on screen side by side")
        }
        let titles = Set(tabs.map(\.title))
        let here = chats.filter { titles.contains($0.title) }
        if here.count == 1 { return .chat(here[0]) }
        return .unclear(here.isEmpty ? "the workspace on screen has no Claude chat"
            : "the workspace on screen has \(here.count) chats and the tab on screen is none of them")
    }

    // MARK: Asking Orca

    /// Where Orca's own command may be: its usual links, then inside the app.
    static var command: String? {
        let home = NSHomeDirectory()
        return ["/usr/local/bin/orca", "/opt/homebrew/bin/orca", "\(home)/.local/bin/orca",
                "/Applications/Orca.app/Contents/Resources/bin/orca", "\(home)/Applications/Orca.app/Contents/Resources/bin/orca"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs Orca's command and returns what it printed, also when it ended with an error:
    /// with `--json` the error is in the answer. Waits at most `seconds`.
    static func run(_ arguments: [String], seconds: Double = 5) -> Result<String, Problem> {
        guard let command else { return .failure(Problem("Orca's command line (orca) is not installed")) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // launchd starts the daemon with a bare PATH, and the command is a script.
        environment["PATH"] = ["/usr/local/bin", "/opt/homebrew/bin", environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
            .joined(separator: ":")
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return .failure(Problem("could not run \(command): \(error.localizedDescription)")) }
        let read = DispatchSemaphore(value: 0)
        let box = Printed()
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }
        guard exited.wait(timeout: .now() + seconds) == .success else {
            process.terminate()
            return .failure(Problem(String(format: "Orca's command did not answer within %.0f s", seconds)))
        }
        _ = read.wait(timeout: .now() + 1)
        return .success(String(decoding: box.data, as: UTF8.self))
    }

    /// What a command printed, handed from the thread that read it.
    private final class Printed: @unchecked Sendable {
        var data = Data()
    }

    /// Asks Orca off the main thread and answers on it.
    static func ask<T: Sendable>(_ arguments: [String], parse: @escaping @Sendable (String) -> Result<T, Problem>,
                                 _ done: @escaping @MainActor @Sendable (Result<T, Problem>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = run(arguments).flatMap(parse)
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }

    // MARK: Orca's window

    /// The tabs of the workspace on screen with their buttons, read from Orca's window, how
    /// many buttons the tab strip has, and why it could not be read, if so.
    @MainActor
    private static func tabButtons() -> (tabs: [(tab: OrcaTab, button: ScreenButton)], strips: Int, problem: String?) {
        // A split view has a tab strip in each part.
        let strips = ScreenButtons.buttons(inBox: tabStrip, bundleID: bundleID)
        let tabs = strips.buttons.compactMap { button in
            tab(shown: ScreenButtons.text(in: button), label: button.label, classes: button.classes).map { ($0, button) }
        }
        return (tabs, strips.boxes, strips.problem)
    }

    /// The tabs of the workspace on screen, read from Orca's window.
    @MainActor
    public static func tabsOnScreen() -> [OrcaTab] {
        tabButtons().tabs.map(\.tab)
    }

    /// What the bridge sees of Orca now, for `micro orca`: its Claude chats, the tabs of the
    /// workspace on screen, and the chat a hold on an empty key would take. It changes nothing.
    /// Titles are left out unless asked for: they are the person's own.
    @MainActor
    public static func look(titles: Bool) -> [String] {
        var lines = ["Orca's command line: " + (command ?? "not found")]
        let started = Date()
        let strip = tabButtons()
        let took = Date().timeIntervalSince(started)
        let tabs = strip.tabs.map(\.tab)
        if let problem = strip.problem {
            lines.append("tabs of the workspace on screen: none read (\(problem))")
        } else {
            let shows = tabs.indices.filter { tabs[$0].selected }.map { String($0 + 1) }
            lines.append("tabs of the workspace on screen: \(tabs.count) in \(strip.strips) tab strip\(strip.strips == 1 ? "" : "s"), "
                + (shows.isEmpty ? "none of them shows" : "tab \(shows.joined(separator: " and ")) shows"))
            if titles { lines += tabs.map { "  " + ($0.selected ? "> " : "  ") + $0.title } }
        }
        lines.append(String(format: "reading Orca's window took %.2f s", took))
        switch run(["agent", "list", "--json"]).flatMap(chats(fromList:)) {
        case let .failure(problem):
            lines.append("Claude chats: none read (\(problem.text))")
        case let .success(chats):
            lines.append("Claude chats: \(chats.count)")
            lines += chats.map { "  \($0.id.prefix(8)) \($0.status.rawValue)" + (titles ? " \($0.title)" : "") }
            switch pick(tabs: tabs, chats: chats) {
            case let .chat(chat): lines.append("a hold on an empty key of Orca's layer would take chat \(chat.id.prefix(8))")
            case let .unclear(why): lines.append("a hold on an empty key of Orca's layer would take no chat: \(why)")
            }
        }
        return lines
    }

    /// How long a jump looks for the chat's tab after its workspace was asked for, and how often.
    private static let tabWait = 3.0
    private static let tabLook = 0.15

    /// Brings Orca to the front, the chat's workspace on screen, and then its tab. `done` hears
    /// what happened, for the log.
    @MainActor
    static func show(_ chat: OrcaChat, _ done: @escaping @MainActor @Sendable (String) -> Void) {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-b", bundleID]
        try? open.run()
        ask(["worktree", "activate", "--worktree", "id:" + chat.worktree, "--json"], parse: { text -> Result<String?, Problem> in
            let root = JSONValue.parse(text)
            return .success(root?["ok"]?.bool == true ? nil : problem(in: root).text)
        }) { result in
            var refused: String?
            switch result {
            case let .success(note): refused = note
            case let .failure(problem): refused = problem.text
            }
            selectTab(of: chat, until: Date().addingTimeInterval(tabWait), workspace: refused, done)
        }
    }

    @MainActor
    private static func selectTab(of chat: OrcaChat, until deadline: Date, workspace refused: String?,
                                  _ done: @escaping @MainActor @Sendable (String) -> Void) {
        let found = tabButtons()
        let its = found.tabs.filter { $0.tab.title == chat.title }.map(\.button)
        let note = refused.map { " (its workspace was not brought on screen: \($0))" } ?? ""
        guard let button = its.first else {
            guard Date() < deadline else {
                done("found no tab with its title among the \(found.tabs.count) tabs of the workspace on screen\(note)"
                    + (found.problem.map { ": \($0)" } ?? ""))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + tabLook) {
                MainActor.assumeIsolated { selectTab(of: chat, until: deadline, workspace: refused, done) }
            }
            return
        }
        let twins = its.count > 1 ? ", the first of \(its.count) tabs with that title" : ""
        if button.classes.contains(selectedTab) {
            done("its tab is on screen already\(twins)\(note)")
        } else {
            done((button.press() ? "its tab is on screen now" : "Orca did not take the press on its tab") + twins + note)
        }
    }
}

/// How the daemon reaches Orca. Tests put a made-up Orca here.
struct OrcaLink {
    typealias Answer<T> = @MainActor @Sendable (Result<T, Orca.Problem>) -> Void

    /// Orca's Claude chats, in every workspace.
    var chats: @MainActor (@escaping Answer<[OrcaChat]>) -> Void = { done in
        Orca.ask(["agent", "list", "--json"], parse: Orca.chats(fromList:), done)
    }
    /// Where one chat is open. Nil when its tab is closed.
    var place: @MainActor (String, @escaping Answer<OrcaChat?>) -> Void = { id, done in
        Orca.ask(["agent", "show", "orca_session_id:" + id, "--json"], parse: Orca.place(fromShow:), done)
    }
    /// The tabs of the workspace on screen.
    var tabs: @MainActor () -> [OrcaTab] = { Orca.tabsOnScreen() }
    /// Brings the chat on screen, and says what happened.
    var show: @MainActor (OrcaChat, @escaping @MainActor @Sendable (String) -> Void) -> Void = { chat, done in
        Orca.show(chat, done)
    }
    /// Seconds between the end of a chat's process and asking Orca whether its tab is closed
    /// too: Orca drops a closed tab a moment after its process.
    var settle: TimeInterval = 0.7
}
