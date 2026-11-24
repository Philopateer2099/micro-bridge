import CoreGraphics
import Foundation
import MicroKit
import MicroUI

let usage = """
usage: micro <command> [--trace]

  app [--demo]    open the MicroBridge window: the pad's lights, keys and settings.
                  --demo shows made-up sessions and writes nothing
  list            show attached pads (does not open them)
  access          show macOS Input Monitoring and Accessibility access, and ask for what is missing
  config path     where the config file lives
  config init     write the default config there, if there is none yet
  config check [file]   say what is wrong with the config, or "ok"
  config show     list what every control does right now
  status          firmware version, battery, layer
  buttons [app] [--watch secs] [--match text] [--detail]
                                 list the buttons in an app's front window (default: the Claude app)
  click <box>[^N]/<pick> [app]   press one of those buttons now, e.g. click "*/Allow once"
  choose <box>/<class>[+<button>]/<next|prev> [app]
                                    move the selection among a box's options now
  key <combo> <bundle id>           type one key combination now, only if that app is in front
  tree <box> [app] [--watch secs] [--attributes]
                                 print everything inside a box (its label, id or class), again on each
                                 change; --attributes lists every accessibility attribute instead
  panes [app] [--names]
                  list the parts of an app's front window that scroll on their own, which is the
                  chat, and where pane:left and pane:right would move the pointer (moves nothing);
                  --names adds each pane's role and classes
  orca [--titles]                what the bridge sees of Orca: its Claude chats, the tabs of the
                                 workspace on screen, and the chat a hold on an empty key of Orca's
                                 layer would take (changes nothing); --titles adds their titles
  record <file>                  say whether a Claude Code session record ends with a turn stopped by hand
  paint           light the six Agent Keys in six different states, left to right
  set <slot> <status>
                  light one Agent Key: working, needs-you, idle, done, failed, off
  listen [secs]   print every key, dial and joystick event (default 60 s, Ctrl-C to stop)
  off             turn every light off
  hold [secs]     through MicroBridge Helper, keep the pad from every other app for a while
                  (default 30 s), then share it again

  daemon [--log]  own the pad and serve the socket (runs until stopped). --log writes its
                  output to ~/Library/Logs/micro-bridge.log
  ctl report <session> <status> [host]
                            tell the daemon what a session is doing (it picks the key);
                            host is claude:local_<id>, where a jump goes, or orca:<id> for a
                            chat in Orca, which goes to the keys of Orca's layer
  ctl end <session>         tell the daemon a session is over (a Claude app session keeps its key,
                            so a press opens it again)
  ctl forget <session>      drop a session and free its key now
  ctl pin <session> [slot]  the session keeps its key (or the key in slot 0 to 5) until it is
                            unpinned or forgotten, however urgent the others are
  ctl unpin <session>       take the pin away
  ctl set <slot> <status>   ask the daemon to light one Agent Key by hand
  ctl clear                 ask the daemon to turn all six off
  ctl orca take <slot> [id] on Orca's layer, key 0 to 5 takes the chat on screen in Orca, as a
                            hold on the empty key does, or the chat with that Orca session ID
  ctl orca free <slot>      that key lets its chat go, as a hold on it does
  ctl orca show <slot>      that key's chat comes on screen in Orca, as a tap on it does
  ctl state                 show what the daemon is showing, and whether the pad is connected
  ctl events                stream key, dial and joystick events from the daemon
  hook                      Claude Code hook: reads the hook's JSON on stdin and reports the
                            session's status to the daemon. Prints nothing, always exits 0.
  hooks status              which Claude Code events call that hook, in ~/.claude/settings.json
  hooks install [--dry-run] add it there, backing the file up first (or creating it). Run it from
                            the app where it will stay: the hook calls this program
  hooks remove [--dry-run]  take it out again. Nothing else in the file changes
                            (--settings <file> works on another settings file)

  The commands above `daemon` open the pad directly; use them only while no daemon runs.

  --trace         print raw HID reports in and out
"""

// Line-buffer stdout: under Launch Services it is a file, which is otherwise block-buffered.
setvbuf(stdout, nil, _IOLBF, 0)
// A client that hangs up before its answer must not take the process down. The per-socket
// option cannot be set once the other end is gone, so ignore the signal for the whole process.
signal(SIGPIPE, SIG_IGN)

var args = Array(CommandLine.arguments.dropFirst())
let trace = args.contains("--trace")
args.removeAll { $0 == "--trace" }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func hexDump(_ bytes: [UInt8]) -> String {
    let length = bytes.count > 2 ? min(Int(bytes[2]) + 3, bytes.count) : bytes.count
    return bytes.prefix(length).map { String(format: "%02x", $0) }.joined(separator: " ")
}

@MainActor func openPad() -> Pad {
    do {
        let pad = try Pad.open()
        if trace {
            pad.onTrace = { bytes, incoming in print(incoming ? "<<" : ">>", hexDump(bytes)) }
        }
        pad.onDebugLine = { print("[firmware]", $0) }
        return pad
    } catch {
        if case .inputMonitoringDenied = error { InputMonitoring.request() }
        fail(error.description)
    }
}

func describe(_ event: PadEvent) -> String {
    switch event {
    case let .key(name, action, agent):
        var parts = ["key", name]
        if let action { parts.append("act=\(action)") }
        if let agent { parts.append("agent=\(agent)") }
        if let slot = event.agentSlot { parts.append("(Agent Key \(slot + 1))") }
        return parts.joined(separator: " ")
    case let .joystick(angle, distance):
        return String(format: "joystick angle=%.3f distance=%.3f", angle, distance)
    case let .unknown(method, params):
        return "notification \(method) \(params.serialized)"
    }
}

@MainActor func run(_ body: (Pad) throws(PadError) -> Void) {
    let pad = openPad()
    do {
        try body(pad)
    } catch {
        pad.close()
        fail(error.description)
    }
    pad.close()
}

let stamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

switch args.first {
case "app":
    MicroApp.run(demo: args.contains("--demo"))

case nil where getppid() == 1:
    // Opened from Finder, the Dock or Spotlight: no command, and launchd as the parent.
    MicroApp.run()

case "snapshot":
    // Development: draws every screen of the window into a folder of PNG files, with made-up
    // sessions, or with `--live` as the bridge and the config file are right now.
    // `--size 900x620` draws the window at another size.
    let live = args.contains("--live")
    args.removeAll { $0 == "--live" }
    var size: CGSize?
    if let at = args.firstIndex(of: "--size"), args.indices.contains(at + 1) {
        let parts = args[at + 1].split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { fail(usage) }
        size = CGSize(width: parts[0], height: parts[1])
        args.removeSubrange(at ... at + 1)
    }
    guard args.count == 2 else { fail(usage) }
    do {
        try MicroApp.snapshot(to: args[1], live: live, size: size)
    } catch {
        fail("\(error)")
    }

case "icon":
    // The app's icon as a PNG file. scripts/bundle makes the bundle's icon from it.
    guard args.count == 2 else { fail(usage) }
    do {
        try MicroApp.writeIcon(to: args[1])
    } catch {
        fail("\(error)")
    }

case "list":
    let pads = Pad.find()
    if pads.isEmpty { fail(PadError.notFound.description) }
    for p in pads {
        let pairs = p.usagePairs.map { String(format: "%04x:%04x", $0.page, $0.usage) }.joined(separator: " ")
        print("\(p.model) pid=\(String(format: "0x%04x", p.productID)) transport=\(p.transport) product=\(p.product ?? "?")")
        print("  usage pairs: \(pairs)")
        print("  report sizes: in=\(p.maxInputReport) out=\(p.maxOutputReport)")
    }

case "access":
    print("Input Monitoring (read the pad):", InputMonitoring.current.rawValue)
    if InputMonitoring.current != .granted {
        print("Requesting access (a system prompt may appear)...")
        print("granted:", InputMonitoring.request())
    }
    print("Accessibility (type keys into apps):", Accessibility.granted ? "granted" : "not granted")
    if !Accessibility.granted {
        print("Requesting access (a system prompt may appear)...")
        print("granted:", Accessibility.request())
    }

case "config":
    let path = args.count > 2 ? args[2] : BridgePaths.config
    switch args.dropFirst().first {
    case "path":
        print(BridgePaths.config)
    case "init":
        if FileManager.default.fileExists(atPath: BridgePaths.config) {
            print("kept the existing \(BridgePaths.config)")
        } else {
            try? FileManager.default.createDirectory(atPath: BridgePaths.directory, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: BridgePaths.config, contents: Data(Config.defaultFileText.utf8),
                                                 attributes: [.posixPermissions: 0o600]) else {
                fail("cannot write \(BridgePaths.config)")
            }
            print("wrote \(BridgePaths.config)")
        }
    case "check", "show":
        let config: Config
        do {
            config = try Config.load(path)
        } catch {
            fail(error.description)
        }
        if args[1] == "check" {
            print("ok: \(config.bindings.count) bindings, \(config.commands.count) commands")
        } else {
            let lighting = config.lighting
            print("brightness \(Int(lighting.brightness * 100)), auto-dim \(lighting.autoDimSeconds == 0 ? "never" : "\(lighting.autoDimSeconds) s"), pulse the key of the session on screen \(lighting.pulseSelected ? "on" : "off"), off when you lock with ⌃⌘Q \(lighting.offWhenLocked ? "on" : "off")")
            print("typed keys go to: \(config.keystrokeApps.isEmpty ? "the app in front" : config.keystrokeApps.joined(separator: ", "))")
            print("leaves the pad to these apps while one is in front: \(config.stepAsideFor.isEmpty ? "none" : config.stepAsideFor.joined(separator: ", "))")
            print("layers that pass the pad to another app: \(config.layers.isEmpty ? "none" : config.layers.sorted { $0.key < $1.key }.map { "\($0.key) to \($0.value)" }.joined(separator: ", "))")
            print("the pad's keys are on those layers too, so one tap passes the pad: \(config.layerKeys ? "yes" : "no")")
            for layer in config.layerApps.keys.sorted() {
                let names = config.layerApps[layer] ?? []
                print("layer \(layer) is the bridge's own, for: \(names.isEmpty ? "no app in particular" : names.joined(separator: ", "))")
            }
            print("wrong-layer notification: \(config.layerWarning ? "on" : "off")")
            print("low-battery notification: \(config.batteryWarning > 0 ? "at \(config.batteryWarning)%" : "off")")
            print("quiet time after a click: \(config.clickGuard > 0 ? "\(config.clickGuard) s" : "off")")
            print("a session without a key takes the key of a less urgent one: \(config.urgentFirst ? "on" : "off")")
            print("a session that ended keeps its key: "
                + (config.rememberHours == .infinity ? "until another session takes it"
                    : config.rememberHours > 0 ? "for \(config.rememberHours) h" : "off"))
            func column(_ text: String, _ width: Int) -> String {
                text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0)
            }
            func list(_ actions: [Action]) -> String {
                actions.isEmpty ? "none" : actions.map(\.description).joined(separator: ", ")
            }
            for (group, ids) in config.apps.sorted(by: { $0.key < $1.key }) {
                print("app group \(group): \(ids.joined(separator: ", "))")
            }
            print("controls:")
            var used: Set<String> = []
            for control in ["AG"] + Config.keyControls + ["STICK", "DIAL"] {
                let mine = config.bindings.filter { $0.key.hasPrefix(control + ".") }
                for actions in mine.values {
                    for case let .command(name, _) in actions { used.insert(name) }
                }
                // A key bound to one command on all four triggers shows as one line.
                let whole = Config.triggers.compactMap { mine["\(control).\($0)"] }
                var shown = mine
                if whole.count == Config.triggers.count, Set(whole.map(list)).count == 1 {
                    print("  \(column(control, 16)) \(list(whole[0]))")
                    for trigger in Config.triggers { shown["\(control).\(trigger)"] = nil }
                }
                for name in shown.keys.sorted() { print("  \(column(name, 16)) \(list(shown[name, default: []]))") }
            }
            print("commands in use (\(config.commands.count) defined):")
            for name in used.sorted() {
                let targets = config.commands[name, default: [:]]
                if targets.isEmpty { print("  \(column(name, 12)) does nothing yet") }
                for target in targets.keys.sorted(by: { ($0 == "default" ? "~" : $0) < ($1 == "default" ? "~" : $1) }) {
                    let triggers = targets[target, default: [:]]
                    let text = triggers.count == 1 && triggers["press"] != nil
                        ? list(triggers["press", default: []])
                        : triggers.keys.sorted().map { "\($0) \(list(triggers[$0, default: []]))" }.joined(separator: "; ")
                    print("  \(column(name, 12)) \(column(target, 9)) \(text)")
                }
            }
        }
    default:
        fail(usage)
    }

case "status":
    run { pad throws(PadError) in
        let version = try pad.call(.version)
        let s = try pad.status()
        print("model:     \(pad.info.model) over \(pad.info.transport)")
        print("version:   \(version?.serialized ?? "?")")
        print("firmware:  \(s.firmware ?? "?")")
        print("battery:   \(s.battery.map { "\($0)%" } ?? "?")\(s.charging == true ? " (charging)" : "")")
        print("profile:   \(s.profile.map(String.init) ?? "?")  layer: \(s.layer.map(String.init) ?? "?")")
    }

case "panes":
    let bundle = args.dropFirst().first { !$0.hasPrefix("--") } ?? "com.anthropic.claudefordesktop"
    let started = Date()
    let layout = ScreenButtons.layout(bundleID: bundle, box: "Prompt")
    let panes = layout.panes
    let took = Int(Date().timeIntervalSince(started) * 1000)
    guard !panes.isEmpty else { fail("no panes found in \(bundle)'s front window (\(took) ms)") }
    func name(_ pane: CGRect) -> String {
        "x \(Int(pane.minX))…\(Int(pane.maxX)), y \(Int(pane.minY))…\(Int(pane.maxY))"
    }
    let merged = Panes.merged(panes)
    let copies = panes.count - merged.count
    print("\(merged.count) panes in \(took) ms, left to right" + (copies > 0 ? " (\(copies) hidden copies left out):" : ":"))
    let chat = layout.box.flatMap { Panes.chat(in: panes, above: $0) }
    for pane in merged.sorted(by: { $0.midX < $1.midX }) { print("  " + name(pane) + (pane == chat ? "  the chat" : "")) }
    if layout.box == nil { print("no message box named Prompt: pane:chat would find no chat") }
    if args.contains("--names") {
        for (pane, what) in ScreenButtons.paneNames(bundleID: bundle) { print("  \(name(pane)): \(what)") }
    }
    let pointer = CGEvent(source: nil)?.location ?? .zero
    print("the pointer is at \(Int(pointer.x)), \(Int(pointer.y))")
    for left in [true, false] {
        let next = Panes.next(from: pointer, in: panes, left: left)
        print("pane:\(left ? "left" : "right") would move it to " + (next.map(name) ?? "nowhere: no pane that way"))
    }

case "buttons":
    // What the pad could press right now in an app's front window.
    // `--watch N` repeats every second for N seconds and prints each time the list changes.
    // `--match text` keeps the buttons whose label, classes or containers hold the text, with
    // two neighbours each side. `--detail` prints every container around each button.
    var bundle = "com.anthropic.claudefordesktop"
    var watch: Double?
    var match: String?
    var detail = false
    var at = 1
    while at < args.count {
        switch args[at] {
        case "--watch":
            at += 1
            watch = args.indices.contains(at) ? Double(args[at]) : nil
        case "--match":
            at += 1
            match = args.indices.contains(at) ? args[at].lowercased() : nil
        case "--detail": detail = true
        default: bundle = args[at]
        }
        at += 1
    }
    func shown(_ listing: ScreenButtons.Listing) -> [Int] {
        guard let match else { return Array(listing.buttons.indices) }
        var keep = Set<Int>()
        for (index, button) in listing.buttons.enumerated()
            where ([button.label] + button.around + button.classes).contains(where: { $0.lowercased().contains(match) }) {
            for near in max(0, index - 2) ... min(listing.buttons.count - 1, index + 2) { keep.insert(near) }
        }
        return keep.sorted()
    }
    func describe(_ listing: ScreenButtons.Listing) -> String {
        var lines: [String] = []
        if let problem = listing.problem { lines.append(problem) }
        for index in shown(listing) {
            let button = listing.buttons[index]
            let frame = button.frame.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? ""
            let id = button.domID.map { "#\($0) " } ?? ""
            lines.append("\(index + 1). \(button.enabled ? "" : "[off] ")\"\(button.label)\" \(id)\(frame)")
            if !button.classes.isEmpty { lines.append("     class: \(button.classes.prefix(detail ? 40 : 8).joined(separator: " "))") }
            if detail {
                for (depth, container) in button.around.enumerated() { lines.append("     in \(depth + 1): \(container)") }
            } else if !button.around.isEmpty {
                lines.append("     in: \(button.around.prefix(4).joined(separator: "  <  "))")
            }
        }
        return lines.joined(separator: "\n")
    }
    if let watch {
        let end = Date().addingTimeInterval(watch)
        var last = ""
        while Date() < end {
            let listing = ScreenButtons.list(bundleID: bundle, detail: detail)
            // Positions shift while text streams in; compare what the buttons are, not where.
            let shape = shown(listing).map { "\(listing.buttons[$0].label)|\(listing.buttons[$0].around.first ?? "")" }.joined(separator: "\n")
            if shape != last {
                last = shape
                print("=== \(stamp.string(from: Date())) \(listing.buttons.count) buttons, \(listing.nodes) elements, \(String(format: "%.2f", listing.seconds)) s")
                print(describe(listing))
            }
            Thread.sleep(forTimeInterval: 1)
        }
    } else {
        let listing = ScreenButtons.list(bundleID: bundle, detail: detail)
        print(describe(listing))
        print("\(listing.buttons.count) buttons, \(listing.nodes) elements, \(String(format: "%.2f", listing.seconds)) s")
    }

case "click":
    // Presses one button now, the way a `click:` action does.
    guard args.count >= 2, let rule = ButtonRule.parse(args[1]) else { fail(usage) }
    let bundle = args.count > 2 ? args[2] : "com.anthropic.claudefordesktop"
    let found = ScreenButtons.find(rule, bundleID: bundle)
    let took = "\(found.nodes) elements, \(String(format: "%.2f", found.seconds)) s"
    guard let button = found.button else {
        let why = found.problem ?? (found.boxShowing ? "not among the \(found.candidates) buttons there" : "its box is not on screen")
        fail("nothing to press for \(rule.spelling): \(why) (\(took))")
    }
    let presses = rule.insist ? button.pressUntilGone() : (button.press() ? 1 : 0)
    print("\(presses > 0 ? "pressed" : "could not press") \"\(button.label)\" (\(took), \(presses) presses)")

case "choose":
    // Moves a card's selection now, the way a `choose:` action does. It types no keys: on a card
    // that takes several answers it moves the highlight, and `mark` is left to the pad.
    guard args.count >= 2, let rule = OptionRule.parse(args[1]) else { fail(usage) }
    let looked = ScreenButtons.card(rule, bundleID: args.count > 2 ? args[2] : "com.anthropic.claudefordesktop")
    let took = "\(looked.nodes) elements, \(String(format: "%.2f", looked.seconds)) s"
    guard let card = looked.card else { fail(looked.problem ?? "no such options on screen (\(took))") }
    if card.many {
        let names = card.places.map { ($0.focused ? ">" : "") + String($0.label.prefix(14)) + ($0.on ? " ON" : "") }.joined(separator: " | ")
        if let target = OptionRule.stop(card.stops, from: card.lit, step: rule.step), card.focus(target) {
            print("takes several answers; highlighted \"\(card.places[target].label)\" (\(took))\n\(names)")
        } else {
            print("takes several answers; the highlight stays where it is (\(took))\n\(names)")
        }
    } else {
        let chosen = ScreenButtons.choose(in: card, step: rule.step)
        if let label = chosen.pressed {
            print("selected \"\(label)\" (\(took), \(chosen.presses) presses\(chosen.took ? "" : ", still off"))")
        } else {
            print("stays where it is, \(chosen.options) options (\(took))")
        }
    }

case "key":
    // Types one key combination into the app in front now, the way a `key:` action does.
    // The app must be named and in front: a key goes to whatever is in front, wanted or not.
    guard args.count >= 3, let action = Action.parse("key:" + args[1]) else { fail(usage) }
    guard ActionRunner.frontApp == args[2] else {
        fail("not typed: \(ActionRunner.frontApp ?? "no app") is in front, not \(args[2])")
    }
    let runner = ActionRunner()
    runner.log = { print($0) }
    runner.keystrokeApps = [args[2]]
    runner.run(action, slot: nil, session: nil)
    usleep(50000)
    print("typed \(args[1]) into \(args[2])")

case "tree":
    // Everything inside a box, for working out what a key could press or focus.
    // `--watch N` waits for the box and prints again each time its contents change.
    guard args.count >= 2 else { fail(usage) }
    // `box^2` prints from two levels above the box: what sits next to it.
    let named = args[1].split(separator: "^", maxSplits: 1).map(String.init)
    let up = named.count == 2 ? Int(named[1]) ?? 0 : 0
    let rule = ButtonRule(box: named[0] == "*" ? "" : named[0], reach: up, pick: .first)
    var bundle = "com.anthropic.claudefordesktop"
    var watch: Double?
    var everything = false
    var at = 2
    while at < args.count {
        if args[at] == "--attributes" {
            everything = true
        } else if args[at] == "--watch" {
            at += 1
            watch = args.indices.contains(at) ? Double(args[at]) : nil
        } else {
            bundle = args[at]
        }
        at += 1
    }
    let read = { everything ? ScreenButtons.attributes(of: rule, bundleID: bundle) : ScreenButtons.tree(of: rule, bundleID: bundle) }
    if let watch {
        let end = Date().addingTimeInterval(watch)
        var last = ""
        while Date() < end {
            let text = read()?.joined(separator: "\n") ?? "(box not on screen)"
            if text != last {
                last = text
                print("=== \(stamp.string(from: Date()))")
                print(text)
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
    } else if let lines = read() {
        print(lines.joined(separator: "\n"))
    } else {
        fail("that box is not on screen")
    }

case "orca":
    // What the bridge sees of Orca, to say why a key took a chat or did not. Reads only.
    guard args.count == 1 || (args.count == 2 && args[1] == "--titles") else { fail(usage) }
    for line in Orca.look(titles: args.count == 2) { print(line) }

case "record":
    // What the daemon reads to notice a turn stopped by hand.
    guard args.count == 2, let tail = Transcript.tail(of: args[1]) else { fail(usage) }
    if let at = Transcript.interruptedAt(tail: tail) {
        print("stopped by hand at \(stamp.string(from: at))")
    } else {
        print("not stopped by hand")
    }

case "paint":
    let order: [AgentStatus] = [.working, .needsYou, .idle, .done, .failed, .off]
    run { pad throws(PadError) in
        try pad.setSlots(order.enumerated().map { $1.light(slot: $0) })
        for (slot, status) in order.enumerated() {
            print("slot \(slot): \(status.rawValue) \(String(format: "#%06X", status.color))")
        }
    }

case "set":
    guard args.count == 3, let slot = Int(args[1]), (0 ... 5).contains(slot),
          let status = AgentStatus(rawValue: args[2]) else { fail(usage) }
    run { pad throws(PadError) in try pad.setSlots([status.light(slot: slot)]) }

case "listen":
    let seconds = args.count > 1 ? Double(args[1]) ?? 60 : 60
    run { pad throws(PadError) in
        pad.onEvent = { event in print(stamp.string(from: Date()), describe(event)) }
        pad.onDisconnect = { print("pad disconnected") }
        print("Listening for \(Int(seconds)) s. Press every key, turn and press the dial, touch the strip, move the joystick.")
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, pad.isConnected { Pad.spin(for: 0.1) }
    }

case "off":
    run { pad throws(PadError) in try pad.allOff() }

case "hold":
    // Through MicroBridge Helper: no other app hears the pad for this long.
    let seconds = Double(args.dropFirst().first ?? "30") ?? 30
    let pad: Pad
    do { pad = try Pad.open() } catch { fail(error.description) }
    guard pad.canHold else {
        fail("MicroBridge Helper is not serving this program\(pad.helperNote.map { ": \($0)" } ?? ": it is not installed (scripts/helper install)").")
    }
    do { try pad.hold(true) } catch { fail(error.description) }
    print("Holding the pad for \(Int(seconds)) s: no other app hears it. Press keys now.")
    var keys = 0, others = 0, otherInput = 0
    pad.onEvent = { _ in keys += 1 }
    pad.onOtherReply = { _, _ in others += 1 }
    pad.onOtherInput = { otherInput += 1 }
    let end = Date().addingTimeInterval(seconds)
    while Date() < end, pad.isConnected { Pad.spin(for: 0.1) }
    try? pad.hold(false)
    pad.close()
    print("Shared again. Key events: \(keys); answers to other apps: \(others); keyboard or mouse reports: \(otherInput).")

case "hooks":
    let rest = Array(args.dropFirst())
    let dryRun = rest.contains("--dry-run")
    var path = ClaudeSettings.path
    if let at = rest.firstIndex(of: "--settings") {
        guard at + 1 < rest.count else { fail("--settings needs a file") }
        path = rest[at + 1]
    }
    do {
        switch rest.first {
        case "status":
            try ClaudeSettings.status(path: path).forEach { print($0) }
        case "install":
            // The hook runs this very program, so it has to stay where it is.
            guard let program = Bundle.main.executablePath,
                  program.hasSuffix("/MicroBridge.app/Contents/MacOS/micro") else {
                fail("Run this from the app: <where it is>/MicroBridge.app/Contents/MacOS/micro hooks install")
            }
            guard !program.contains("/AppTranslocation/") else {
                fail("macOS is running MicroBridge from a temporary copy. Move it to Applications, open it once, then run this again.")
            }
            try ClaudeSettings.change(path: path, adding: ClaudeSettings.command(executable: program), dryRun: dryRun)
                .forEach { print($0) }
        case "remove":
            try ClaudeSettings.change(path: path, adding: nil, dryRun: dryRun).forEach { print($0) }
        default:
            fail("usage: micro hooks status | install [--dry-run] | remove [--dry-run]")
        }
    } catch {
        fail(error.description)
    }

case "hook":
    // A hook must never slow down or break Claude Code: no output, short timeout, exit 0.
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let claudes = ProcessTree.claudeCodeAncestors()
    if input.count <= 4 << 20, let payload = JSONValue.parse(String(decoding: input, as: UTF8.self)),
       let request = ClaudeHook.request(for: payload, pid: claudes.first,
                                        environment: ProcessInfo.processInfo.environment, nested: claudes.count > 1) {
        try? SocketClient.send(request, timeout: 1) { _ in false }
    }
    exit(0)

case "daemon":
    // Started from the app's login item, nothing points its output at the log: --log does
    // (scripts/install's LaunchAgent sets the same file itself).
    if args.contains("--log") {
        let path = NSHomeDirectory() + "/Library/Logs/micro-bridge.log"
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if freopen(path, "a", stdout) != nil { setvbuf(stdout, nil, _IOLBF, 0) }
        freopen(path, "a", stderr)
    }
    do {
        try Daemon().run()
    } catch {
        fail(error.description)
    }

case "ctl":
    func object(_ pairs: [(String, JSONValue)]) -> String { JSONValue.object(pairs).serialized }
    let request: String
    var streaming = false
    switch args.dropFirst().first {
    case "report":
        guard args.count == 4 || args.count == 5 else { fail(usage) }
        var pairs: [(String, JSONValue)] = [
            ("op", .string("report")), ("session", .string(args[2])), ("status", .string(args[3])),
        ]
        if args.count == 5 { pairs.append(("host", .string(args[4]))) }
        request = object(pairs)
    case "end", "forget", "unpin":
        guard args.count == 3 else { fail(usage) }
        request = object([("op", .string(args[1])), ("session", .string(args[2]))])
    case "pin":
        guard args.count == 3 || args.count == 4 else { fail(usage) }
        var pairs: [(String, JSONValue)] = [("op", .string("pin")), ("session", .string(args[2]))]
        if args.count == 4 {
            guard let slot = Int(args[3]) else { fail(usage) }
            pairs.append(("slot", .number(Double(slot))))
        }
        request = object(pairs)
    case "set":
        guard args.count == 4, let slot = Int(args[2]) else { fail(usage) }
        request = object([("op", .string("set")), ("slot", .number(Double(slot))), ("status", .string(args[3]))])
    case "clear": request = object([("op", .string("clear"))])
    case "orca":
        guard args.count == 4 || (args.count == 5 && args[2] == "take"), ["take", "free", "show"].contains(args[2]),
              let slot = Int(args[3]) else { fail(usage) }
        var pairs: [(String, JSONValue)] = [("op", .string("orca." + args[2])), ("slot", .number(Double(slot)))]
        if args.count == 5 { pairs.append(("session", .string(args[4]))) }
        request = object(pairs)
    case "state": request = object([("op", .string("state"))])
    case "events":
        request = object([("op", .string("subscribe"))])
        streaming = true
    default: fail(usage)
    }
    var failed = false
    do {
        try SocketClient.send(request) { reply in
            if JSONValue.parse(reply)?["ok"]?.bool == false { failed = true }
            print(reply)
            return streaming
        }
    } catch {
        fail(error.description)
    }
    if failed { exit(1) }

default:
    print(usage)
}
