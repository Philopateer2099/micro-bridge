import MicroKit
import SwiftUI

/// A trigger as the file names it and as the window words it.
struct TriggerName: Hashable {
    var name: String
    var title: String

    init(_ name: String, _ title: String) {
        self.name = name
        self.title = title
    }

    /// The triggers of a command, and of a key with its own actions.
    static let ofKeys = [
        TriggerName("press", "Press"), TriggerName("release", "Release"), TriggerName("doubleTap", "Double tap"),
        TriggerName("hold", "Hold"),
    ]
}

extension PadControl {
    /// The control's name in the bridge's bindings.
    var controlName: String {
        switch self {
        case .agents: "AG"
        case let .key(name): name
        case .dial: "DIAL"
        case .stick: "STICK"
        }
    }

    var owner: ActionList.Owner {
        switch self {
        case .agents: .section("agentKeys")
        case let .key(name): .key(name)
        case .dial: .section("dial")
        case .stick: .section("stick")
        }
    }

    var triggers: [TriggerName] {
        switch self {
        case .agents:
            [TriggerName("press", "Tap"), TriggerName("doubleTap", "Double tap"), TriggerName("hold", "Hold"),
             TriggerName("release", "Release"), TriggerName("empty", "Tap, no session")]
        case .key:
            TriggerName.ofKeys
        case .dial:
            // On this pad a turn to the right arrives as "ccw".
            [TriggerName("ccw", "Turn right"), TriggerName("cw", "Turn left"), TriggerName("press", "Press"),
             TriggerName("doubleTap", "Double tap"), TriggerName("hold", "Hold"), TriggerName("release", "Release")]
        case .stick:
            Config.stickDirections.map { TriggerName($0, $0.capitalized) }
        }
    }

    /// The triggers the editor lists even when they do nothing.
    var mainTriggers: Set<String> {
        switch self {
        case .agents, .key: ["press"]
        case .dial: ["ccw", "cw", "press"]
        case .stick: Set(Config.stickDirections)
        }
    }
}

/// Everything one control, or one command in one app, does: a list of actions per trigger.
struct TriggerLists: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var state: WindowState
    var owner: ActionList.Owner
    var triggers: [TriggerName]
    /// The triggers to list even when they do nothing.
    var main: Set<String>
    var emptyNote = "Nothing."

    var body: some View {
        let stored = Dictionary(model.lists(of: owner).map { ($0.trigger, $0.actions) }, uniquingKeysWith: { first, _ in first })
        let shown = triggers.filter { trigger in
            main.contains(trigger.name) || !(stored[trigger.name] ?? []).isEmpty
                || state.opened.contains(ActionList(owner: owner, trigger: trigger.name).id)
        }
        let hidden = triggers.filter { !shown.contains($0) }
        return Card {
            ForEach(Array(shown.enumerated()), id: \.element) { index, trigger in
                if index > 0 { Divider().padding(.leading, 16) }
                ActionRows(model: model, state: state, list: ActionList(owner: owner, trigger: trigger.name),
                           title: trigger.title, actions: stored[trigger.name] ?? [], emptyNote: emptyNote)
            }
            if !hidden.isEmpty {
                Divider().padding(.leading, 16)
                Menu("Add a trigger") {
                    ForEach(hidden, id: \.self) { trigger in
                        Button(trigger.title) { state.opened.insert(ActionList(owner: owner, trigger: trigger.name).id) }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
    }
}

/// One list of actions, in the order the bridge runs them. A field is saved with Return or
/// its Save button, never while it is being typed: a half-written action must not reach a key.
struct ActionRows: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var state: WindowState
    var list: ActionList
    var title: String
    var actions: [String]
    var emptyNote: String

    private var inCommand: Bool { list.owner.inCommand }

    /// Where a row's draft is kept. A row past the end is an action that is being added.
    func rowID(_ index: Int) -> String { "\(list.id)#\(index)" }

    var body: some View {
        // A row past the end is an action that is being added.
        let adding = state.drafts[rowID(actions.count)] != nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                addMenu
            }
            if actions.isEmpty, !adding {
                Text(emptyNote).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(0 ..< actions.count + (adding ? 1 : 0)), id: \.self) { index in
                row(index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var addMenu: some View {
        Menu {
            kindButtons { add($0) }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .controlSize(.small)
        .help("Add an action to the end of this list")
    }

    @ViewBuilder private func kindButtons(_ pick: @escaping (ActionKind) -> Void) -> some View {
        let groups = ActionKind.groups(inCommand: inCommand)
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group) { kind in
                Button(kind.title) { pick(kind) }
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let stored = index < actions.count ? ActionDraft(spelling: actions[index]) : nil
        let draft = state.drafts[rowID(index)]
        let shown = draft ?? stored
        let problem = draft?.problem(inCommand: inCommand)
        let note = note(shown, problem: problem)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .trailing)
                if let shown {
                    kindPicker(shown, at: index)
                    if !shown.kind.isLong { valueControl(shown, at: index) }
                } else {
                    // Text the bridge does not read as an action. It can only be taken out.
                    Text(actions[index]).font(.system(.callout, design: .monospaced)).foregroundStyle(.red).lineLimit(1)
                }
                Spacer(minLength: 0)
                if draft == nil { rowMenu(index) }
            }
            if let shown, shown.kind.isLong {
                // What these kinds take is long, so it gets a line of its own.
                HStack(spacing: 8) { valueControl(shown, at: index) }.padding(.leading, 22)
            }
            if note != nil || draft != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let note {
                        Text(note.text).font(.caption).foregroundStyle(note.bad ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if draft != nil {
                        Button(index < actions.count ? "Save" : "Add") { commit(index) }.disabled(problem != nil)
                        Button("Cancel") { state.drafts[rowID(index)] = nil }
                    }
                }
                .padding(.leading, 22)
            }
        }
        .controlSize(.small)
    }

    /// The line under a row: why it cannot be saved, or what a terse action means.
    private func note(_ shown: ActionDraft?, problem: String?) -> (text: String, bad: Bool)? {
        guard let shown else { return ("The bridge does not know this action. Take it out, or fix it in the file.", true) }
        if let problem {
            // An empty field is not a mistake yet.
            return (problem, !shown.value.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        guard shown.kind.isKey || shown.kind == .click || shown.kind == .choose,
              let action = Action.parse(shown.spelling) else { return nil }
        return (action.plainWords, false)
    }

    private func kindPicker(_ shown: ActionDraft, at index: Int) -> some View {
        Picker("", selection: Binding(
            get: { shown.kind },
            set: { setKind($0, at: index) }
        )) {
            kindOptions
        }
        .labelsHidden()
        // Kinds with a value beside them have short names; the others have the row to themselves.
        .frame(minWidth: 92, maxWidth: shown.kind.isLong || !shown.kind.takesValue ? 220 : 150)
    }

    @ViewBuilder private var kindOptions: some View {
        let groups = ActionKind.groups(inCommand: inCommand)
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group) { kind in
                Text(kind.title).tag(kind)
            }
        }
    }

    @ViewBuilder
    private func valueControl(_ shown: ActionDraft, at index: Int) -> some View {
        switch shown.kind {
        case .command:
            let names = model.commandNames
            Picker("", selection: Binding(
                get: { shown.value },
                set: { name in
                    var next = shown
                    next.value = name
                    change(to: next, at: index, saveNow: true)
                }
            )) {
                if !names.contains(shown.value) {
                    Text(shown.value.isEmpty ? "Choose a command" : shown.value).tag(shown.value)
                    Divider()
                }
                ForEach(names, id: \.self) { name in
                    Text(model.title(name)).tag(name)
                }
            }
            .labelsHidden()
            .frame(minWidth: 56, maxWidth: 240)
            .help("cmd:" + shown.value)
        case .text:
            field(shown, at: index)
            Toggle("then Return", isOn: Binding(
                get: { shown.sends },
                set: { sends in
                    var next = shown
                    next.sends = sends
                    // A box that is ticked on a saved row is saved at once; on a row that
                    // is being typed it waits for the rest.
                    change(to: next, at: index, saveNow: state.drafts[rowID(index)] == nil)
                }
            ))
            .toggleStyle(.checkbox)
            .fixedSize()
            .help("Press Return after the text, which sends it")
        case _ where !shown.kind.takesValue:
            EmptyView()
        case _ where shown.kind.isKey:
            field(shown, at: index).frame(minWidth: 56, maxWidth: 170)
        default:
            field(shown, at: index)
        }
    }

    private func field(_ shown: ActionDraft, at index: Int) -> some View {
        TextField(shown.kind.placeholder, text: Binding(
            get: { shown.value },
            set: { text in
                guard text != shown.value else { return }
                var next = shown
                next.value = text
                change(to: next, at: index, saveNow: false)
            }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.system(.callout, design: .monospaced))
        .onSubmit { commit(index) }
    }

    private func rowMenu(_ index: Int) -> some View {
        Menu {
            Button("Move up") { move(index, by: -1) }.disabled(index == 0)
            Button("Move down") { move(index, by: 1) }.disabled(index >= actions.count - 1)
            Divider()
            Button("Remove") { remove(index) }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move or remove this action")
    }

    // MARK: Changes

    /// Gives a row another kind. A key stays the same key when only how it is pressed changes.
    func setKind(_ kind: ActionKind, at index: Int) {
        let shown = state.drafts[rowID(index)] ?? (index < actions.count ? ActionDraft(spelling: actions[index]) : nil)
        guard kind != shown?.kind else { return }
        var next = ActionDraft(kind: kind)
        if kind.isKey, let shown, shown.kind.isKey { next.value = shown.value }
        change(to: next, at: index, saveNow: true)
    }

    /// Keeps a change as a draft, or writes it now when it is complete and `saveNow` says so.
    func change(to next: ActionDraft, at index: Int, saveNow: Bool) {
        if saveNow, next.problem(inCommand: inCommand) == nil {
            write(next, at: index)
        } else if index < actions.count, ActionDraft(spelling: actions[index]) == next {
            state.drafts[rowID(index)] = nil
        } else {
            state.drafts[rowID(index)] = next
        }
    }

    /// Return in a field, or the row's Save button.
    func commit(_ index: Int) {
        guard let draft = state.drafts[rowID(index)], draft.problem(inCommand: inCommand) == nil else { return }
        write(draft, at: index)
    }

    private func write(_ draft: ActionDraft, at index: Int) {
        var next = actions
        if index < next.count { next[index] = draft.spelling } else { next.append(draft.spelling) }
        if model.setActions(next, in: list) { state.drafts[rowID(index)] = nil }
    }

    func add(_ kind: ActionKind) {
        let draft = ActionDraft(kind: kind)
        state.opened.insert(list.id)
        if draft.problem(inCommand: inCommand) == nil {
            state.clearDrafts(of: list)
            model.setActions(actions + [draft.spelling], in: list)
        } else {
            state.drafts[rowID(actions.count)] = draft
        }
    }

    func move(_ index: Int, by step: Int) {
        guard actions.indices.contains(index), actions.indices.contains(index + step) else { return }
        var next = actions
        next.swapAt(index, index + step)
        state.clearDrafts(of: list)
        model.setActions(next, in: list)
    }

    func remove(_ index: Int) {
        guard actions.indices.contains(index) else { return }
        var next = actions
        next.remove(at: index)
        // The list stays on screen when its last action goes.
        state.opened.insert(list.id)
        state.clearDrafts(of: list)
        model.setActions(next, in: list)
    }
}

// MARK: - Commands

struct CommandsTab: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var state: WindowState

    /// The command on screen: the picked one, or the first when that one is gone.
    private var selected: String? {
        model.config.commands[state.command] != nil ? state.command : model.allCommands.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Commands").font(.system(size: 24, weight: .semibold))
                Text("A command is a named set of actions that can differ from app to app. Give one to a key on the Keys screen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 16)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                names.frame(width: 250)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let selected { detail(selected) }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    TextField("New command", text: $state.newCommand)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(state.newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.small)
                if let problem = state.newCommandProblem {
                    Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.allCommands, id: \.self) { name in
                        nameRow(name)
                    }
                }
                .padding(8)
            }
        }
    }

    private func nameRow(_ name: String) -> some View {
        let uses = model.uses(of: name)
        let title = model.title(name)
        return Button {
            state.command = name
        } label: {
            HStack(spacing: 9) {
                CommandCap(face: model.face(ofCommand: name), unit: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).lineLimit(1)
                    if title != name {
                        Text(name).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if let first = uses.first {
                    Text(uses.count > 1 ? "\(first) +\(uses.count - 1)" : first)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .opacity(model.commandDoesSomething(name) ? 1 : 0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected == name ? Theme.chosen : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add() {
        let name = state.newCommand.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        state.newCommandProblem = model.addCommand(name)
        if state.newCommandProblem == nil {
            state.command = name.uppercased()
            state.newCommand = ""
        }
    }

    @ViewBuilder private func detail(_ name: String) -> some View {
        let uses = model.uses(of: name)
        let builtIn = model.commandIsBuiltIn(name)
        let isDefault = model.commandIsDefault(name)
        let everywhere = model.lists(of: .command(name, target: "default")).contains { !$0.actions.isEmpty }
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.title(name)).font(.title2.weight(.semibold))
            Text("cmd:" + name).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            Text(builtIn ? (isDefault ? "default" : "changed") : "yours")
                .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        Text(uses.isEmpty ? "No control runs it yet. Pick it as a keycap on the Keys screen."
            : "Runs from: " + uses.joined(separator: ", ") + ".")
            .font(.callout).foregroundStyle(.secondary)
        ForEach(model.commandTargets(name), id: \.self) { target in
            SectionTitle(model.targetTitle(target)).padding(.top, 4)
            TriggerLists(model: model, state: state, owner: .command(name, target: target),
                         triggers: TriggerName.ofKeys, main: ["press"],
                         emptyNote: target != "default" && everywhere ? "The same as everywhere else." : "Nothing.")
        }
        Text("An app with no actions of its own does what “Everywhere else” says. "
            + "A numbered list is tried in order: a step that finds its button or its answers on screen ends the list.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
            if builtIn {
                if !isDefault { Button("Back to the default") { remove(name) } }
            } else {
                Button("Delete the command") { remove(name) }
                    .disabled(!uses.isEmpty)
                    .help(uses.isEmpty ? "Take this command out of the file" : "Take it off \(uses.joined(separator: ", ")) first")
            }
            Button("Open the config file") { model.openInEditor(model.files.config) }
        }
        .padding(.top, 4)
    }

    private func remove(_ name: String) {
        state.drafts = state.drafts.filter { !$0.key.hasPrefix("commands/\(name)/") }
        model.removeCommand(name)
    }
}
