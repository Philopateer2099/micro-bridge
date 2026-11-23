import SwiftUI

/// The dialog a key on the Keys screen opens: every command as a keycap to pick from, and
/// whether the key runs that command, its own actions or nothing. Nothing reaches the file
/// until Save.
struct KeycapDialog: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var state: WindowState
    let key: String

    /// What the Actions row says the key runs.
    enum Mode: Hashable { case command, own, nothing }

    private var current: Keycap { model.keycap(key).cap }
    private var draft: Keycap { state.keycapDraft }

    /// The commands on offer: the ones on the pad, the ones a person made, then the rest.
    var names: [String] {
        var names = model.allCommands.filter(model.commandDoesSomething)
        // A key may run a command that does nothing yet. It stays on offer while it is the key's.
        if case let .command(name) = current, !names.contains(name) { names.insert(name, at: 0) }
        let query = state.keycapSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return names }
        return names.filter {
            $0.localizedCaseInsensitiveContains(query) || model.title($0).localizedCaseInsensitiveContains(query)
        }
    }

    var mode: Mode {
        switch draft {
        case .command: .command
        case .custom: .own
        case .nothing: .nothing
        }
    }

    /// Nothing is picked that the key does not already have.
    var unchanged: Bool {
        switch (draft, current) {
        case let (.command(picked), .command(now)): picked == now
        case (.custom, .custom), (.nothing, .nothing): true
        default: false
        }
    }

    func pick(_ name: String) {
        state.keycapDraft = .command(name)
    }

    func setMode(_ mode: Mode) {
        switch mode {
        case .own: state.keycapDraft = .custom("")
        case .nothing: state.keycapDraft = .nothing
        case .command:
            if case .command = draft { return }
            // Back to a command: the key's own one, else the first on offer.
            if case let .command(name) = current { pick(name) } else if let first = names.first { pick(first) }
        }
    }

    func cancel() {
        state.keycapKey = nil
    }

    func save() {
        if !unchanged {
            switch draft {
            case let .command(name): model.setKeycap(key, to: name)
            case .nothing: model.setKeycap(key, to: nil)
            case .custom: model.giveKeyOwnActions(key)
            }
        }
        state.keycapKey = nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 16) {
            header
            search
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
                        ForEach(names, id: \.self) { tile($0).id($0) }
                    }
                    .padding(2)
                    if names.isEmpty {
                        Text("No command has that in its name. Make one on the Commands screen.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 28)
                    }
                }
                // The key's own keycap is on show when the dialog opens.
                .onAppear {
                    if case let .command(name) = draft { proxy.scrollTo(name, anchor: .center) }
                }
            }
            .frame(maxHeight: 408)
            actions
            HStack(spacing: 14) {
                Spacer()
                Button("Cancel") { cancel() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button { save() } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.dialog)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary))
                }
                .buttonStyle(.plain)
                .opacity(unchanged ? 0.45 : 1)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 548)
        .background(shape.fill(Theme.dialog))
        .overlay(shape.strokeBorder(Theme.line))
        .shadow(color: Color.black.opacity(0.35), radius: 30, y: 12)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Keycap for \(PadControl.key(key).title)").font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    Text("Choose the command this key runs.").foregroundStyle(.secondary)
                    Text(PadControl.key(key).fileName).font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 13))
            }
            Spacer()
            Button { cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Close without saving")
        }
    }

    private var search: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search commands", text: $state.keycapSearch).textFieldStyle(.plain)
                .accessibilityLabel("Search commands")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.14)))
    }

    /// One command as a keycap: its picture over its name in the file.
    private func tile(_ name: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let chosen = draft == .command(name)
        return Button { pick(name) } label: {
            VStack(spacing: 8) {
                Group {
                    if case let .symbol(symbol) = model.face(ofCommand: name) {
                        Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.92))
                    } else {
                        // A command with no picture of its own: a bare cap.
                        Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2).frame(width: 13, height: 13)
                    }
                }
                .frame(height: 18)
                Text(name)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(shape.fill(chosen ? PadColors.keyChosen : PadColors.key))
            .overlay(shape.strokeBorder(chosen ? Color.white.opacity(0.85) : PadColors.keyEdge, lineWidth: chosen ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(model.title(name))
        .accessibilityLabel(model.title(name) == name ? name : "\(model.title(name)), \(name)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var actionsDetail: String {
        switch draft {
        case let .command(name): "The command's: \(model.title(name))."
        case .custom: "One list per trigger. They are under the pad after Save."
        case .nothing: "The key does nothing."
        }
    }

    private var actions: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return SettingRow(title: "Actions", detail: actionsDetail) {
            Picker("", selection: Binding(get: { mode }, set: { setMode($0) })) {
                Text("The keycap's command").tag(Mode.command)
                Text("Its own actions").tag(Mode.own)
                Text("Nothing").tag(Mode.nothing)
            }
            .labelsHidden()
            .fixedSize()
        }
        .background(shape.fill(Theme.card))
        .overlay(shape.strokeBorder(Theme.line))
    }
}
