import Darwin

/// Turns Claude Code hook payloads into daemon requests.
public enum ClaudeHook {
    /// Tools that stop and wait for the person, without a permission prompt.
    static let askingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// What the session is doing after this hook event, or nil when the event says nothing new.
    /// `.off` means the session is over.
    public static func status(for payload: JSONValue) -> AgentStatus? {
        switch payload["hook_event_name"]?.string {
        case "SessionStart":
            // Compaction restarts the session in the middle of a turn; it is still working.
            return payload["source"]?.string == "compact" ? nil : .idle
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "ElicitationResult":
            return .working
        case "PreToolUse":
            return askingTools.contains(payload["tool_name"]?.string ?? "") ? .needsYou : .working
        case "PermissionRequest", "Elicitation":
            return .needsYou
        case "Stop":
            return .done
        case "StopFailure":
            return .failed
        case "SessionEnd":
            return .off
        default:
            return nil
        }
    }

    /// True for a session the pad stays out of: one started in an Orca terminal (Orca sets
    /// `ORCA_TERMINAL_HANDLE` there) that is not a Claude app session. Those get no
    /// Agent Key and no light, on purpose (see docs/configuration.md).
    static func isLeftAlone(_ environment: [String: String]) -> Bool {
        environment["CLAUDE_CODE_HOST_SESSION_ID"] == nil && environment["ORCA_TERMINAL_HANDLE"]?.isEmpty == false
    }

    /// The line to send the daemon for this payload, or nil when there is nothing to send.
    /// `environment` is the hook's own, inherited from Claude Code: it names the Claude app
    /// session this session lives in, when it lives in one.
    public static func request(for payload: JSONValue, pid: Int?, environment: [String: String] = [:]) -> String? {
        guard !isLeftAlone(environment) else { return nil }
        guard let session = payload["session_id"]?.string, !session.isEmpty,
              let status = status(for: payload) else { return nil }
        if status == .off {
            return JSONValue.object([("op", .string("end")), ("session", .string(session))]).serialized
        }
        var pairs: [(String, JSONValue)] = [
            ("op", .string("report")), ("session", .string(session)), ("status", .string(status.rawValue)),
        ]
        if let pid { pairs.append(("pid", .number(Double(pid)))) }
        if let cwd = payload["cwd"]?.string { pairs.append(("cwd", .string(cwd))) }
        if let host = SessionHost(environment: environment) { pairs.append(("host", .string(host.description))) }
        // The daemon reads the record to notice a turn stopped by hand, which fires no hook.
        if let record = payload["transcript_path"]?.string, record.hasPrefix("/"), record.utf8.count <= 2048 {
            pairs.append(("transcript", .string(record)))
        }
        return JSONValue.object(pairs).serialized
    }
}

/// Finds the Claude Code process a hook runs under, so the daemon can tell when it is gone.
public enum ProcessTree {
    /// True for the Claude Code program itself: `…/claude` (desktop app, npm) or the native
    /// install's `…/claude/versions/<version>`. The desktop app `Claude` does not count.
    public static func isClaudeCode(path: String) -> Bool {
        path.hasSuffix("/claude") || path.contains("/claude/versions/")
    }

    public static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// The nearest ancestor of this process that is Claude Code.
    public static func claudeCodeAncestor() -> Int? {
        var pid = getppid()
        for _ in 0 ..< 8 where pid > 1 {
            if let path = path(of: pid), isClaudeCode(path: path) { return Int(pid) }
            guard let next = parent(of: pid) else { return nil }
            pid = next
        }
        return nil
    }

    public static func isAlive(_ pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0 || errno == EPERM
    }

    /// When the process started, in seconds since 1970, or nil when there is no such process.
    public static func started(_ pid: Int) -> Double? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
    }
}
