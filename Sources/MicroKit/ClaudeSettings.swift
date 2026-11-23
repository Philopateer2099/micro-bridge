import Foundation

/// The bridge's hook in Claude Code's user settings, `~/.claude/settings.json`: whether it is
/// there, and the file with it added or taken out. Only entries that run MicroBridge's own
/// `micro hook` change; everything else is written back as it was, in the same order.
///
/// The MicroBridge plugin for Claude Code is the other way to add the hook (D-024). The two must
/// not both be on, or each event would reach the bridge twice.
public enum ClaudeSettings {
    /// The events `micro hook` understands, and whether each takes a matcher.
    public static let events: [(name: String, matcher: Bool)] = [
        ("SessionStart", false), ("UserPromptSubmit", false), ("PreToolUse", true), ("PostToolUse", true),
        ("PostToolUseFailure", true), ("PermissionRequest", true), ("Elicitation", true),
        ("ElicitationResult", true), ("Stop", false), ("StopFailure", false), ("SessionEnd", false),
    ]

    /// The plugin as `enabledPlugins` names it: the plugin, then its marketplace.
    public static let pluginID = "micro-bridge@micro-bridge"

    public static var path: String { NSHomeDirectory() + "/.claude/settings.json" }

    /// The hook command for the program at `executable`.
    public static func command(executable: String) -> String { shellQuoted(executable) + " hook" }

    /// What a person runs in Terminal to add the hook for the program at `executable`.
    public static func installCommand(executable: String) -> String { shellQuoted(executable) + " hooks install" }

    /// How many events reach the bridge: all of them when the plugin is on, else those whose
    /// hooks in the file run it. No file counts as none; nil means the file is not JSON.
    public static func reportingEvents(path: String) -> Int? {
        guard let settings = try? read(path).settings else { return nil }
        return pluginEnabled(settings) ? events.count : registered(settings).count
    }

    /// A path as a shell reads it: as it is when it holds only safe characters, else in single
    /// quotes. The same rule as Python's `shlex.quote`, which wrote the hooks before this did.
    static func shellQuoted(_ text: String) -> String {
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if text.isEmpty { return "''" }
        if text.allSatisfy(safe.contains) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Whether a hook command runs a copy of MicroBridge's `micro hook`, wherever the app is.
    static func runsBridge(_ command: String) -> Bool {
        guard command.hasSuffix(" hook") else { return false }
        var program = String(command.dropLast(" hook".count))
        if program.count >= 2, program.hasPrefix("'"), program.hasSuffix("'") {
            program = String(program.dropFirst().dropLast())
        }
        return program.hasSuffix("/MicroBridge.app/Contents/MacOS/micro")
    }

    private static func items(_ value: JSONValue?) -> [JSONValue] {
        if case let .array(items)? = value { return items }
        return []
    }

    private static func members(_ value: JSONValue?) -> [(String, JSONValue)] {
        if case let .object(pairs)? = value { return pairs }
        return []
    }

    /// The events whose hooks run the bridge, in the file's order.
    public static func registered(_ settings: JSONValue) -> [String] {
        members(settings["hooks"]).compactMap { event, groups in
            items(groups).contains { group in
                items(group["hooks"]).contains { runsBridge($0["command"]?.string ?? "") }
            } ? event : nil
        }
    }

    /// Whether the MicroBridge plugin is switched on in these settings.
    public static func pluginEnabled(_ settings: JSONValue) -> Bool {
        settings["enabledPlugins"]?[pluginID]?.bool == true
    }

    /// The settings with `command` on every event. An entry that runs the bridge from another
    /// place (the app was moved) is pointed at the new one rather than added a second time.
    public static func installing(_ command: String, into settings: JSONValue) -> JSONValue {
        var hooks = JSONValue.object(members(settings["hooks"]))
        for (event, takesMatcher) in events {
            var groups = items(hooks[event])
            let entries = groups.flatMap { items($0["hooks"]) }
            if entries.contains(where: { $0["command"]?.string == command }) { continue }
            if entries.contains(where: { runsBridge($0["command"]?.string ?? "") }) {
                groups = groups.map { group in
                    guard case .object = group, case let .array(list)? = group["hooks"] else { return group }
                    return group.setting("hooks", .array(list.map { hook in
                        runsBridge(hook["command"]?.string ?? "") ? hook.setting("command", .string(command)) : hook
                    }))
                }
            } else {
                var group: [(String, JSONValue)] = takesMatcher ? [("matcher", .string("*"))] : []
                group.append(("hooks", .array([.object([
                    ("type", .string("command")), ("command", .string(command)), ("timeout", .number(5)),
                ])])))
                groups.append(.object(group))
            }
            hooks = hooks.setting(event, .array(groups))
        }
        return settings.setting("hooks", hooks)
    }

    /// The settings without any hook that runs the bridge. A group left with no hooks goes, and
    /// so does an event left with no groups.
    public static func removing(from settings: JSONValue) -> JSONValue {
        guard case .object = settings["hooks"] else { return settings }
        var kept: [(String, JSONValue)] = []
        for (event, groups) in members(settings["hooks"]) {
            guard case let .array(list) = groups else {
                kept.append((event, groups))
                continue
            }
            let remaining = list.compactMap { group -> JSONValue? in
                let hooks = items(group["hooks"])
                guard hooks.contains(where: { runsBridge($0["command"]?.string ?? "") }) else { return group }
                let rest = hooks.filter { !runsBridge($0["command"]?.string ?? "") }
                return rest.isEmpty ? nil : group.setting("hooks", .array(rest))
            }
            if !remaining.isEmpty { kept.append((event, .array(remaining))) }
        }
        return settings.setting("hooks", .object(kept))
    }

    // MARK: The file

    public enum Problem: Error, CustomStringConvertible, Equatable {
        case notJSON(String)
        case pluginOn
        case changedWhileRunning
        case cannotWrite(String)

        public var description: String {
            switch self {
            case let .notJSON(path): "\(path) is not a JSON object. Fix it first; nothing was written."
            case .pluginOn:
                "The MicroBridge plugin is on in Claude Code and already reports every event. Adding the hook here "
                    + "too would report each one twice. Nothing was written."
            case .changedWhileRunning: "The settings file changed while this ran. Nothing was written; run it again."
            case let .cannotWrite(why): "Could not write the settings: \(why)"
            }
        }
    }

    /// Reads the settings file. Nil text when there is no file yet, which counts as no settings.
    static func read(_ path: String) throws(Problem) -> (text: String?, settings: JSONValue) {
        guard let data = FileManager.default.contents(atPath: path) else { return (nil, .object([])) }
        let text = String(decoding: data, as: UTF8.self)
        guard let settings = JSONValue.parseKeepingOrder(text), case .object = settings else { throw .notJSON(path) }
        return (text, settings)
    }

    /// What `micro hooks status` prints.
    public static func status(path: String) throws(Problem) -> [String] {
        let settings = try read(path).settings
        let found = registered(settings)
        var lines = ["\(found.count) of \(events.count) events call MicroBridge's hook in \(path)"]
        let missing = events.map(\.name).filter { !found.contains($0) }
        if !found.isEmpty, !missing.isEmpty { lines.append("missing: " + missing.joined(separator: ", ")) }
        if pluginEnabled(settings) { lines.append("the MicroBridge plugin is on in Claude Code") }
        return lines
    }

    /// Adds the hook (`command` set) or takes it out (`command` nil), and says what it did.
    /// An existing file is backed up next to itself first; a new one is readable only by you.
    public static func change(path: String, adding command: String?, dryRun: Bool,
                              now: Date = Date()) throws(Problem) -> [String] {
        let (before, settings) = try read(path)
        if command != nil, pluginEnabled(settings) { throw .pluginOn }
        let changed = command.map { installing($0, into: settings) } ?? removing(from: settings)
        // Equal settings mean nothing to do, even when the file is laid out differently.
        if changed == settings { return ["nothing to change"] }
        let after = changed.indented + "\n"
        let had = Set(registered(settings))
        let has = Set(registered(changed))
        let (would, did): (String, String) = switch command {
        case nil: ("remove the hook from \(had.subtracting(has).count) events",
                   "removed the hook from \(had.subtracting(has).count) events")
        case let command? where has == had: ("point the hook at \(command)", "pointed the hook at \(command)")
        case _: ("add the hook to \(has.subtracting(had).count) events", "added the hook to \(has.subtracting(had).count) events")
        }
        if dryRun { return ["would \(would) in \(path) (dry run, nothing written)"] }

        let manager = FileManager.default
        var lines: [String] = []
        var mode: Int = 0o600
        if let before {
            let backup = try backUp(before, path: path, now: now)
            mode = ((try? manager.attributesOfItem(atPath: path)[.posixPermissions]) as? Int) ?? 0o600
            guard let current = manager.contents(atPath: path), String(decoding: current, as: UTF8.self) == before else {
                throw .changedWhileRunning
            }
            lines.append("\(did) in \(path)")
            lines.append("backup: \(backup)")
        } else {
            let folder = (path as NSString).deletingLastPathComponent
            do {
                try manager.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            } catch { throw .cannotWrite(error.localizedDescription) }
            if manager.fileExists(atPath: path) { throw .changedWhileRunning }
            lines.append("created \(path) and \(did)")
        }
        let temp = path + ".micro-tmp"
        unlink(temp)
        guard manager.createFile(atPath: temp, contents: Data(after.utf8), attributes: [.posixPermissions: mode]),
              rename(temp, path) == 0
        else {
            unlink(temp)
            throw .cannotWrite(String(cString: strerror(errno)))
        }
        return lines
    }

    /// Copies the file's text next to it, under a name with the time. Two changes in one second
    /// would pick the same name, so a later one gets a number.
    private static func backUp(_ text: String, path: String, now: Date) throws(Problem) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = path + ".bak-micro-" + format.string(from: now)
        for n in 1 ..< 100 {
            let name = n == 1 ? stamp : "\(stamp)-\(n)"
            let fd = open(name, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            if fd < 0 {
                if errno == EEXIST { continue }
                throw .cannotWrite(String(cString: strerror(errno)))
            }
            let bytes = Array(text.utf8)
            let wrote = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
            guard wrote == bytes.count else { throw .cannotWrite("the backup was cut short") }
            return name
        }
        throw .cannotWrite("could not pick a backup name")
    }
}
