import MicroKit
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case pad, keys, commands, lights, behavior, setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pad: "Pad"
        case .keys: "Keys"
        case .commands: "Commands"
        case .lights: "Lights"
        case .behavior: "Behavior"
        case .setup: "Setup"
        }
    }

    var symbol: String {
        switch self {
        case .pad: "square.grid.2x2.fill"
        case .keys: "keyboard"
        case .commands: "command"
        case .lights: "lightbulb.fill"
        case .behavior: "slider.horizontal.3"
        case .setup: "checklist"
        }
    }
}

/// Which screen the window shows, what is picked on it and what is being typed. It is an object
/// and not `@State`, because `@State` needs a compiler plugin that only Xcode ships, and this
/// package builds with the Command Line Tools alone.
@MainActor
final class WindowState: ObservableObject {
    @Published var tab: Tab
    /// The control the Keys screen shows.
    @Published var selection: PadControl
    /// The command the Commands screen shows.
    @Published var command: String
    /// Actions that are being typed and are not in the file yet, by list and place in it.
    @Published var drafts: [String: ActionDraft] = [:]
    /// The lists a person opened with "Add a trigger". They show while they are still empty.
    @Published var opened: Set<String> = []
    @Published var newCommand = ""
    @Published var newCommandProblem: String?
    /// The key whose keycap dialog is open.
    @Published var keycapKey: String?
    /// What is picked in that dialog and not saved yet.
    @Published var keycapDraft: Keycap = .nothing
    @Published var keycapSearch = ""

    init(tab: Tab = .pad, selection: PadControl = .key("ACT07"), command: String = "APPR") {
        self.tab = tab
        self.selection = selection
        self.command = command
    }

    /// Opens the keycap dialog for a key, with what the key has now picked in it.
    func editKeycap(_ key: String, current: Keycap) {
        keycapDraft = current
        keycapSearch = ""
        keycapKey = key
    }

    func clearDrafts(of list: ActionList) {
        drafts = drafts.filter { !$0.key.hasPrefix(list.id + "#") }
    }
}

struct RootView: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var state: WindowState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            detail
        }
        // The title bar is see-through: the sidebar runs under the window's buttons.
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if let key = state.keycapKey {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { state.keycapKey = nil }
                    KeycapDialog(model: model, state: state, key: key).padding(24)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let notice = model.notice {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Dismiss") { model.notice = nil }.controlSize(.small)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12))
            }
            switch state.tab {
            case .pad: PadTab(model: model)
            case .keys: KeysTab(model: model, state: state)
            case .commands: CommandsTab(model: model, state: state)
            case .lights: LightsTab(model: model)
            case .behavior: BehaviorTab(model: model)
            case .setup: SetupTab(model: model)
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.window)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                PadMark(side: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MicroBridge").font(.system(size: 15, weight: .semibold))
                    Text("for Claude Code").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 48)
            .padding(.bottom, 16)

            ForEach(Tab.allCases) { item in
                Button {
                    state.tab = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol).frame(width: 18)
                            .foregroundStyle(state.tab == item ? Color.primary : Color.secondary)
                        Text(item.title)
                        Spacer()
                        if item == .setup, model.nextStep != nil {
                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(state.tab == item ? Theme.chosen : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            footer
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 208)
        .background(Theme.sidebar)
    }

    private var footer: some View {
        let bridge = model.bridge
        let line: (dot: Color, title: String, detail: String) = {
            if !bridge.running { return (.red, "Bridge not running", "Open Setup to start it") }
            if !bridge.connected { return (.orange, "Pad not connected", "Plug it in with USB") }
            var parts = [bridge.transport ?? "USB"]
            if let battery = bridge.battery { parts.append("\(battery)%" + (bridge.charging == true ? ", charging" : "")) }
            return (.green, "Pad connected", parts.joined(separator: " · "))
        }()
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(line.dot).frame(width: 8, height: 8).shadow(color: line.dot.opacity(0.8), radius: 4).padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.title).font(.callout.weight(.medium))
                    Text(line.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            if bridge.running, bridge.connected, let battery = bridge.battery {
                // How full the battery is.
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(battery <= 15 ? Color.red : Color.green)
                            .frame(width: max(4, 164 * CGFloat(min(max(battery, 0), 100)) / 100), height: 4)
                    }
                    .frame(width: 164, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.card))
        .overlay(shape.strokeBorder(Theme.line))
    }
}

// MARK: - Parts

/// A screen: its title, then cards in one column in the middle of the window.
struct Page<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    /// The widest the column of cards gets.
    static var column: CGFloat { 680 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 24, weight: .semibold))
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 10)
                content
            }
            .frame(maxWidth: Self.column, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }
}

struct SettingRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 14, weight: .medium)).padding(.top, 12)
    }
}

struct StepBanner: View {
    var step: NextStep

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.right.circle.fill").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Next step").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(step.text).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let button = step.button {
                Button(button) { step.run?() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
    }
}

/// Rows of a card with a line between them.
struct Rows<Item: Hashable, Row: View>: View {
    var items: [Item]
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element) { index, item in
            if index > 0 { Divider().padding(.leading, 16) }
            row(item)
        }
    }
}

// MARK: - Pad

struct PadTab: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        Page(title: "Pad", subtitle: "What each Agent Key shows right now. Click a lit key to open its session.") {
            if let step = model.nextStep { StepBanner(step: step) }
            Card {
                SettingRow(title: "Connection", detail: nil) {
                    Text(connection.text).foregroundStyle(connection.color)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Battery", detail: nil) {
                    if let battery = model.bridge.battery, model.bridge.running, model.bridge.connected {
                        HStack(spacing: 5) {
                            Image(systemName: battery > 60 ? "battery.100percent" : battery > 25 ? "battery.50percent" : "battery.25percent")
                                .foregroundStyle(.secondary)
                            Text("\(battery)%").monospacedDigit().foregroundStyle(.secondary)
                            if model.bridge.charging == true { Image(systemName: "bolt.fill").foregroundStyle(.green) }
                        }
                    } else {
                        Text("Not known").foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Input Monitoring", detail: "macOS lets the bridge read the pad's keys.") {
                    Text(inputMonitoring.text).foregroundStyle(inputMonitoring.color)
                }
                Divider().padding(.leading, 16)
                LightRows(model: model)
            }
            SectionTitle("Layout")
            PadCard {
                PadDrawing(slots: model.bridge.slots, pulsing: model.bridge.pulsing, pinned: model.pinnedSlots,
                           color: { Color(rgb: model.rgb($0)) }, faces: model.faces, names: model.keyNames,
                           tapped: { _, slot in
                               if let slot, let session = model.session(onSlot: slot) { model.open(session) }
                           })
            }
            SectionTitle("Agent Keys")
            Card {
                Rows(items: Array(0 ..< 6)) { slot in
                    SessionLine(model: model, number: slot + 1, session: model.session(onSlot: slot))
                }
            }
            Text("A pinned session keeps its key until you unpin or forget it, however urgent the others are.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.waiting.isEmpty {
                SectionTitle("Waiting for a key")
                Card {
                    Rows(items: model.waiting.map(\.id)) { id in
                        SessionLine(model: model, number: nil, session: model.waiting.first { $0.id == id })
                    }
                }
            }
            SectionTitle("Options")
            Card {
                SettingRow(title: "Agent Keys", detail: "Which sessions the six keys show when more than six are open.") {
                    Picker("", selection: Binding(
                        get: { model.config.urgentFirst },
                        set: { model.set(.bool($0), at: ["urgentFirst"]) }
                    )) {
                        Text("The most urgent").tag(true)
                        Text("The first six").tag(false)
                    }
                    .labelsHidden().fixedSize()
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Dial", detail: "What turning the dial moves through. A press and a hold stay as they are.") {
                    Picker("", selection: Binding(get: { model.dialTurn }, set: { model.setDialTurn($0) })) {
                        Text("Answers in a prompt").tag(DialTurn.answers)
                        Text("Sessions").tag(DialTurn.sessions)
                        if model.dialTurn == .own { Text("Your own").tag(DialTurn.own) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
    }

    private var inputMonitoring: (text: String, color: Color) {
        guard model.bridge.running, let access = model.bridge.inputMonitoring else { return ("Not known", .secondary) }
        return access == InputMonitoring.granted.rawValue ? ("Granted", .green) : ("Not granted: see Setup", .orange)
    }

    /// How the pad is reached, with what it says about itself.
    private var connection: (text: String, color: Color) {
        let bridge = model.bridge
        if !bridge.running { return ("The bridge is not running", .red) }
        if !bridge.connected { return ("Not connected", .orange) }
        var parts = ["Connected", bridge.transport ?? "USB"]
        if let firmware = bridge.firmware { parts.append("firmware " + firmware) }
        if let layer = bridge.layer { parts.append("layer \(layer)") }
        return (parts.joined(separator: " · "), .secondary)
    }
}

struct SessionLine: View {
    @ObservedObject var model: BridgeModel
    var number: Int?
    var session: SessionRow?

    var body: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(session?.name ?? (number.map { "Key \($0)" } ?? "No session"))
                    .font(.system(size: 13, weight: session == nil ? .regular : .medium))
                    .foregroundStyle(session == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                if let session {
                    Text((number.map { "Key \($0) · " } ?? "") + session.status.label + (session.ended ? " · ended" : "")
                        + (session.pinned ? " · pinned" : ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(session.ended ? "Its Claude Code process is over. A tap on its key opens it again." : "")
                }
            }
            Spacer(minLength: 8)
            if let session {
                if session.host != nil { Button("Open") { model.open(session) } }
                pinMenu(session)
                Button("Forget") { model.forget(session) }
                    .help("Drop this session and free its key. A running session takes a key again when it next does something.")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func pinMenu(_ session: SessionRow) -> some View {
        Menu {
            if session.pinned {
                Button("Unpin") { model.unpin(session) }
            } else {
                Button(session.slot == nil ? "Pin to a key" : "Pin to this key") { model.pin(session) }
            }
            Divider()
            ForEach(Array(0 ..< 6).filter { $0 != session.slot }, id: \.self) { slot in
                Button("Pin to key \(slot + 1)") { model.pin(session, to: slot) }
            }
        } label: {
            Image(systemName: session.pinned ? "pin.fill" : "pin")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(session.pinned ? "Pinned: it keeps this key. Click to unpin or move it."
            : "Pin it, so no other session takes its key.")
    }

    private var badge: some View {
        let status = session?.status ?? .off
        return AgentCap(light: status == .off ? nil : Color(rgb: model.rgb(status)), glows: false, unit: 28)
    }
}

// MARK: - Keys

struct KeysTab: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var state: WindowState

    private var selection: PadControl { state.selection }

    var body: some View {
        Page(title: "Keys", subtitle: "Click a key to choose its keycap. Click the dial, the stick or an Agent Key to set it up.") {
            HStack(alignment: .lastTextBaseline) {
                SectionTitle("Layout")
                Spacer()
                Button("Open the config file") { model.openInEditor(model.files.config) }
                    .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            PadCard {
                PadDrawing(slots: Array(repeating: .off, count: 6), color: { _ in .clear }, faces: model.faces, names: model.keyNames,
                           selection: selection, showsLights: false, tapped: { control, _ in
                               state.selection = control
                               // A key opens its keycap dialog. The other controls are set up under the pad.
                               if case let .key(name) = control { state.editKeycap(name, current: model.keycap(name).cap) }
                           })
            }
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                SectionTitle(selection.title)
                Text(selection.fileName).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                if isDefault { Chip("default") }
                Spacer()
                if !isDefault {
                    Button("Back to the default") { reset() }
                        .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
            editor
            SectionTitle("What it does now")
            doesCard
        }
    }

    private var isDefault: Bool {
        switch selection {
        case let .key(name): model.keycap(name).isDefault
        case .agents: model.sectionIsDefault("agentKeys")
        case .dial: model.sectionIsDefault("dial")
        case .stick: model.sectionIsDefault("stick")
        }
    }

    private func reset() {
        switch selection {
        case let .key(name): model.resetKey(name)
        case .agents: model.set(nil, at: ["agentKeys"])
        case .dial: model.set(nil, at: ["dial"])
        case .stick: model.set(nil, at: ["stick"])
        }
    }

    @ViewBuilder private var editor: some View {
        switch selection {
        case let .key(name):
            let cap = model.keycap(name).cap
            Card {
                SettingRow(title: "Keycap", detail: capDetail(cap)) {
                    HStack(spacing: 10) {
                        CommandCap(face: model.face(name), unit: 28)
                        Text(capName(cap))
                        Button("Change") { state.editKeycap(name, current: cap) }
                    }
                }
                if case let .command(command) = cap {
                    Divider().padding(.leading, 16)
                    SettingRow(title: "What \(model.title(command)) does",
                               detail: "A command can do something different in each app, and on a press, a release, a double tap and a hold.") {
                        Button("Edit the command") {
                            state.command = command
                            state.tab = .commands
                        }
                    }
                }
            }
            if case .custom = cap { lists }
        case .agents:
            Card {
                SettingRow(title: "Hold a key to forget its session",
                           detail: "A tap still opens the session. It runs when you let go of the key.") {
                    Toggle("", isOn: Binding(
                        get: { model.trigger("hold", of: "agentKeys") == .string("forget") },
                        set: { model.setTrigger("hold", of: "agentKeys", to: $0 ? .string("forget") : nil) }
                    )).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Double tap a key to pin or unpin its session",
                           detail: "The key blinks twice when it pins and once when it unpins. The first tap still opens the session.") {
                    Toggle("", isOn: Binding(
                        get: { model.trigger("doubleTap", of: "agentKeys") == .string("pin") },
                        set: { model.setTrigger("doubleTap", of: "agentKeys", to: $0 ? .string("pin") : nil) }
                    )).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "A dark key starts a new chat",
                           detail: "Off: a key with no session does nothing.") {
                    Toggle("", isOn: Binding(
                        get: { model.trigger("empty", of: "agentKeys") != nil },
                        set: { model.setTrigger("empty", of: "agentKeys", to: $0 ? .string("open:claude://code/new") : nil) }
                    )).labelsHidden().toggleStyle(.switch)
                }
            }
            lists
        case .dial:
            Card {
                SettingRow(title: "Turn direction",
                           detail: "If turning right moves the wrong way, swap the two directions.") {
                    Button("Swap") { model.swapDial() }
                }
            }
            lists
        case .stick:
            lists
        }
    }

    /// The control's actions, one list per trigger.
    @ViewBuilder private var lists: some View {
        SectionTitle("Actions")
        TriggerLists(model: model, state: state, owner: selection.owner, triggers: selection.triggers,
                     main: selection.mainTriggers)
        Text("These are the same in every app. For actions that differ from app to app, make a command on the Commands screen and run it from here.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func capName(_ cap: Keycap) -> String {
        switch cap {
        case let .command(name): model.title(name) == name ? name : "\(model.title(name))  (\(name))"
        case .nothing: "Nothing"
        case .custom: "Its own actions"
        }
    }

    private func capDetail(_ cap: Keycap) -> String? {
        switch cap {
        case .command: nil
        case .nothing: "This key does nothing."
        case .custom: "One list per trigger."
        }
    }

    private var doesRows: [(label: String, claude: [Action], terminal: [Action])] {
        selection.triggers.compactMap { trigger in
            let does = model.does(selection.controlName, trigger.name)
            return does.claude.isEmpty && does.terminal.isEmpty ? nil : (trigger.title, does.claude, does.terminal)
        }
    }

    private var doesCard: some View {
        let rows = doesRows
        let chained = rows.contains { ($0.claude + $0.terminal).contains(where: \.endsListWhenItWorks) }
        return VStack(alignment: .leading, spacing: 8) {
            Card {
                if rows.isEmpty {
                    Text("Nothing.").foregroundStyle(.secondary).padding(16)
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 12) {
                        GridRow {
                            Text("")
                            Text("In the Claude app").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("In a terminal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        ForEach(rows, id: \.label) { row in
                            GridRow {
                                Text(row.label).gridColumnAlignment(.leading)
                                actionList(row.claude)
                                actionList(row.terminal)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            if chained {
                Text("A numbered list is tried in order. A step that finds its button or its answers on screen ends the list.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One action per line, in plain words. The file's own spelling is the tooltip.
    private func actionList(_ actions: [Action]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if actions.isEmpty { Text("–").foregroundStyle(.secondary) }
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Text((actions.count > 1 ? "\(index + 1). " : "") + action.plainWords)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(action.description)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lights

struct LightsTab: View {
    @ObservedObject var model: BridgeModel

    private let statuses: [AgentStatus] = [.idle, .working, .needsYou, .done, .failed]

    var body: some View {
        Page(title: "Lights", subtitle: "The color of each state, and how bright the keys are.") {
            PadCard {
                HStack(spacing: 6) {
                    ForEach(statuses, id: \.self) { status in
                        VStack(spacing: 8) {
                            AgentCap(light: Color(rgb: model.rgb(status)).opacity(0.3 + 0.7 * model.config.lighting.brightness),
                                     unit: 50)
                            Text(status.label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.6))
                                .lineLimit(1).frame(width: 82)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PadColors.body))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(PadColors.edge))
            }
            Card {
                Rows(items: statuses) { status in
                    SettingRow(title: status.label, detail: status.meaning) {
                        ColorPicker("", selection: Binding(
                            get: { Color(rgb: model.rgb(status)) },
                            set: { color in if let rgb = color.rgb { model.setColor(status, to: rgb) } }
                        ), supportsOpacity: false).labelsHidden()
                    }
                }
            }
            Card {
                LightRows(model: model)
                Divider().padding(.leading, 16)
                SettingRow(title: "Pulse the key of the session on screen",
                           detail: "The key of the session the Claude app shows breathes slowly.") {
                    Toggle("", isOn: Binding(
                        get: { model.config.lighting.pulseSelected },
                        set: { model.set(.bool($0), at: ["lighting", "pulseSelected"]) }
                    )).labelsHidden().toggleStyle(.switch)
                }
            }
            if !model.colorsAreDefault { Button("Back to the default colors") { model.resetColors() } }
        }
    }
}

/// Brightness, auto-dim and the lock: on the Pad screen, as on the Codex app's page, and on
/// Lights. macOS refuses every write to the pad once the Mac is locked, so the lock switch
/// works only for ⌃⌘Q, which the bridge catches and lets through after the lights are off.
struct LightRows: View {
    @ObservedObject var model: BridgeModel

    private static let waits = [0, 60, 180, 300, 900, 3600]

    var body: some View {
        let lighting = model.config.lighting
        SettingRow(title: "Brightness", detail: "Every light on the pad.") {
            Slider(value: Binding(
                get: { lighting.brightness * 100 },
                // To the nearest 5 without a step, so the slider has no tick marks.
                set: { model.set(.number(($0 / 5).rounded() * 5), at: ["lighting", "brightness"]) }
            ), in: 5 ... 100).frame(width: 180)
            Text("\(Int((lighting.brightness * 100).rounded()))%")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
        Divider().padding(.leading, 16)
        SettingRow(title: "Auto-dim", detail: "Lights off after a quiet spell. A press or a change of status turns them on.") {
            Picker("", selection: Binding(
                get: { lighting.autoDimSeconds },
                set: { model.set(.number(Double($0)), at: ["lighting", "autoDimSeconds"]) }
            )) {
                Text("Never").tag(0)
                Text("1 minute").tag(60)
                Text("3 minutes").tag(180)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
                Text("1 hour").tag(3600)
                if !Self.waits.contains(lighting.autoDimSeconds) {
                    Text("\(lighting.autoDimSeconds) seconds").tag(lighting.autoDimSeconds)
                }
            }
            .labelsHidden().fixedSize()
        }
        Divider().padding(.leading, 16)
        SettingRow(title: "Lights off when you lock with ⌃⌘Q",
                   detail: "The bridge turns them off, then the Mac locks. Locking another way leaves them on: macOS blocks the pad once the Mac is locked.") {
            Toggle("", isOn: Binding(
                get: { lighting.offWhenLocked },
                set: { model.set(.bool($0), at: ["lighting", "offWhenLocked"]) }
            )).labelsHidden().toggleStyle(.switch)
        }
    }
}

// MARK: - Behavior

struct BehaviorTab: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        Page(title: "Behavior", subtitle: "How sessions get keys, and what the bridge warns you about.") {
            Card {
                SettingRow(title: "The most urgent sessions hold the keys",
                           detail: "With more than six sessions, one that needs you takes the key of one that is only idle.") {
                    Toggle("", isOn: Binding(
                        get: { model.config.urgentFirst },
                        set: { model.set(.bool($0), at: ["urgentFirst"]) }
                    )).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "A session that ended keeps its key",
                           detail: "A tap on the key opens the session again in the Claude app.") {
                    Picker("", selection: Binding(
                        get: { model.config.rememberHours.isInfinite ? -1 : model.config.rememberHours },
                        set: { model.set($0 < 0 ? .string("always") : .number($0), at: ["rememberHours"]) }
                    )) {
                        Text("Until another session takes it").tag(-1.0)
                        Text("For 1 hour").tag(1.0)
                        Text("For 8 hours").tag(8.0)
                        Text("For 24 hours").tag(24.0)
                        Text("Never").tag(0.0)
                        if ![-1, 0, 1, 8, 24].contains(model.config.rememberHours.isInfinite ? -1 : model.config.rememberHours) {
                            Text("For \(model.config.rememberHours.formatted()) hours").tag(model.config.rememberHours)
                        }
                    }
                    .labelsHidden().frame(width: 230)
                }
            }
            Card {
                SettingRow(title: "Low battery warning",
                           detail: "One notification when the pad runs low and is not charging.") {
                    Picker("", selection: Binding(
                        get: { model.config.batteryWarning },
                        set: { model.set(.number(Double($0)), at: ["batteryWarning"]) }
                    )) {
                        Text("Off").tag(0)
                        ForEach([10, 20, 30, 50], id: \.self) { Text("At \($0)%").tag($0) }
                        if ![0, 10, 20, 30, 50].contains(model.config.batteryWarning) {
                            Text("At \(model.config.batteryWarning)%").tag(model.config.batteryWarning)
                        }
                    }
                    .labelsHidden().frame(width: 120)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Warn when the pad is on another layer",
                           detail: "On any layer but the first, the pad's keys do not reach the bridge.") {
                    Toggle("", isOn: Binding(
                        get: { model.config.layerWarning },
                        set: { model.set(.bool($0), at: ["layerWarning"]) }
                    )).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Ignore a second press right after a button press",
                           detail: "Keeps a double press of Approve from answering two prompts.") {
                    Picker("", selection: Binding(
                        get: { model.config.clickGuard },
                        set: { model.set(.number($0), at: ["clickGuard"]) }
                    )) {
                        Text("Off").tag(0.0)
                        Text("For half a second").tag(0.5)
                        Text("For 1 second").tag(1.0)
                        Text("For 2 seconds").tag(2.0)
                        if ![0, 0.5, 1, 2].contains(model.config.clickGuard) {
                            Text("For \(model.config.clickGuard.formatted()) seconds").tag(model.config.clickGuard)
                        }
                    }
                    .labelsHidden().frame(width: 170)
                }
            }
            Card {
                SettingRow(title: "Leave the pad to ChatGPT while it is in front",
                           detail: "Both apps hear every key. While ChatGPT is in front, MicroBridge "
                               + "lights nothing and acts on no key. In any other app, its lights win.") {
                    Toggle("", isOn: Binding(
                        get: { model.config.stepAsideFor.contains(PadSharing.chatGPT) },
                        set: { on in
                            let others = model.config.stepAsideFor.filter { $0 != PadSharing.chatGPT }
                            let apps = on ? [PadSharing.chatGPT] + others : others
                            model.set(.array(apps.map(JSONValue.string)), at: ["stepAsideFor"])
                        }
                    )).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: model.config.layerKeys
                    ? "One tap passes the pad to ChatGPT" : "Two taps pass the pad to ChatGPT",
                    detail: model.config.layerKeys
                        ? "Tap the pad's touch sensor to go to layer 2: ChatGPT drives the pad there. "
                        + "Tap again to come back to layer 1: MicroBridge drives it. The app in front "
                        + "does not matter."
                        : "Tap the pad's touch sensor to go to layer 2, wait for the notification, "
                        + "then tap again to come back. From then on ChatGPT drives the pad, and the "
                        + "same two taps give it back. Until then MicroBridge drives it, whatever "
                        + "app is in front.") {
                    Toggle("", isOn: Binding(
                        get: { model.config.layers[2] == PadSharing.chatGPT },
                        set: { on in
                            model.set(on ? .string(PadSharing.chatGPT) : nil, at: ["layers", "2"])
                        }
                    )).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 16)
                SettingRow(title: "Layer 2 has the pad's keys too",
                           detail: "Turn this on after you put the Codex keys on layer 2 with Work Louder "
                               + "Input. Then one tap is enough: the layer the pad is on says who drives it.") {
                    Toggle("", isOn: Binding(
                        get: { model.config.layerKeys },
                        set: { model.set(.bool($0), at: ["layerKeys"]) }
                    )).labelsHidden().toggleStyle(.switch)
                }
                .disabled(model.config.layers.isEmpty)
                Divider().padding(.leading, 16)
                SettingRow(title: "Typed keys go to",
                           detail: model.config.keystrokeApps.isEmpty
                               ? "Whichever app is in front."
                               : model.config.keystrokeApps.joined(separator: ", ")) {
                    Button("Change in the file") { model.openInEditor(model.files.config) }
                }
            }
        }
    }
}

// MARK: - Setup

struct SetupTab: View {
    @ObservedObject var model: BridgeModel

    private enum Mark {
        case good, warning, bad, unknown
    }

    private struct Check: Hashable {
        var mark: Mark
        var title: String
        var detail: String
    }

    var body: some View {
        Page(title: "Setup", subtitle: "What the pad needs to work, from the bridge down to the cable.") {
            if let step = model.nextStep {
                StepBanner(step: step)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                    Text("Everything is working.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.opacity(0.12)))
            }
            Card {
                Rows(items: checks) { check in
                    HStack(alignment: .top, spacing: 12) {
                        icon(check.mark).frame(width: 20).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                            Text(check.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            HStack {
                switch model.loginStart {
                case .off: Button("Start at login") { model.startAtLogin() }
                case .on: Button("Don't start at login") { model.stopAtLogin() }
                case .needsApproval: Button("Open Login Items") { model.openLoginItems() }
                case .scripts, .unavailable: EmptyView()
                }
                Button("Restart the bridge") { model.restartBridge() }
                Button("Open the config file") { model.openInEditor(model.files.config) }
                Button("Open the log") { model.openInEditor(model.files.log) }
            }
            SectionTitle("Bridge log")
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    if model.log.isEmpty {
                        Text("No log yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                        Text(Self.shown(line))
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func icon(_ mark: Mark) -> some View {
        switch mark {
        case .good: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .bad: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private var checks: [Check] {
        let bridge = model.bridge
        var list: [Check] = []
        list.append(bridge.running
            ? Check(mark: .good, title: "Bridge", detail: "Running.")
            : Check(mark: .bad, title: "Bridge", detail: "Not running."))
        switch model.loginStart {
        case .scripts: list.append(Check(mark: .good, title: "Start at login", detail: "Started at login by scripts/install."))
        case .on: list.append(Check(mark: .good, title: "Start at login",
                                    detail: "On. It is listed under System Settings > General > Login Items."))
        case .needsApproval: list.append(Check(mark: .warning, title: "Start at login",
                                               detail: "Allow MicroBridge under System Settings > General > Login Items."))
        case .off: list.append(Check(mark: .bad, title: "Start at login", detail: "Off. The bridge will not start when you log in."))
        case .unavailable: break
        }

        func access(_ title: String, granted: Bool?, good: String, bad: String) -> Check {
            guard bridge.running else { return Check(mark: .unknown, title: title, detail: "The bridge has to run to say.") }
            guard let granted else {
                return Check(mark: .unknown, title: title, detail: "The running bridge is older than this window and does not say. Restart it.")
            }
            return Check(mark: granted ? .good : .bad, title: title, detail: granted ? good : bad)
        }
        list.append(access("Input Monitoring", granted: bridge.inputMonitoring.map { $0 == InputMonitoring.granted.rawValue },
                           good: "macOS lets the bridge read the pad's keys.",
                           bad: "Switch MicroBridge on under System Settings > Privacy & Security > Input Monitoring."))
        list.append(access("Accessibility", granted: bridge.accessibility,
                           good: "macOS lets the bridge type keys and press buttons.",
                           bad: "Switch MicroBridge on under System Settings > Privacy & Security > Accessibility."))

        let wanted = BridgeModel.hookEventsWanted
        switch model.hookEvents {
        case nil:
            list.append(Check(mark: .unknown, title: "Claude Code hooks", detail: "~/.claude/settings.json is not valid JSON."))
        case 0?:
            list.append(Check(mark: .bad, title: "Claude Code hooks",
                              detail: "Claude Code does not report to the bridge. Run this in Terminal: \(model.hookCommand)\n"
                                  + "Or add the plugin in Claude Code: /plugin marketplace add Philopateer2099/micro-bridge, "
                                  + "then install micro-bridge."))
        case let count? where count < wanted:
            list.append(Check(mark: .warning, title: "Claude Code hooks",
                              detail: "\(count) of \(wanted) events report to the bridge. Run this in Terminal: \(model.hookCommand)"))
        default:
            list.append(Check(mark: .good, title: "Claude Code hooks", detail: "All \(wanted) events report to the bridge."))
        }

        list.append(model.problems.isEmpty
            ? Check(mark: .good, title: "Config file", detail: "config.json is valid.")
            : Check(mark: .bad, title: "Config file", detail: model.problems.joined(separator: "\n")))

        if bridge.connected {
            var parts = ["Connected over \(bridge.transport ?? "USB")."]
            if let firmware = bridge.firmware { parts.append("Firmware \(firmware).") }
            if let battery = bridge.battery { parts.append("Battery \(battery)%" + (bridge.charging == true ? ", charging." : ".")) }
            let away = bridge.layer.map { !model.config.isOwn(layer: $0) } ?? false
            if away { parts.append("It is on layer \(bridge.layer ?? 0), where its keys are off.") }
            if let layer = bridge.layer, !away, layer != LayerWatch.ours {
                parts.append("It is on layer \(layer), one of MicroBridge's own.")
            }
            list.append(Check(mark: away ? .warning : .good, title: "Pad", detail: parts.joined(separator: " ")))
        } else if bridge.running {
            list.append(Check(mark: .warning, title: "Pad", detail: "Not connected. Plug it in with its USB cable."))
        } else {
            list.append(Check(mark: .unknown, title: "Pad", detail: "The bridge has to run to say."))
        }
        return list
    }

    /// A log line with its time in this Mac's time zone.
    private static func shown(_ line: String) -> String {
        guard let space = line.firstIndex(of: " "),
              let date = ISO8601DateFormatter().date(from: String(line[..<space])) else { return line }
        return date.formatted(date: .omitted, time: .standard) + line[space...]
    }
}
