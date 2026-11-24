import MicroKit
import SwiftUI

/// A control on the pad that the config file can bind.
enum PadControl: Hashable {
    /// The six Agent Keys share one binding.
    case agents
    case key(String)
    case dial
    case stick

    var title: String {
        switch self {
        case .agents: "Agent Keys"
        case let .key(name): Self.keyTitles[name] ?? name
        case .dial: "Dial"
        case .stick: "Stick"
        }
    }

    /// The name the config file uses.
    var fileName: String {
        switch self {
        case .agents: "agentKeys"
        case let .key(name): "keys." + name
        case .dial: "dial"
        case .stick: "stick"
        }
    }

    static let keyTitles = Config.controlTitles.filter { ["ACT06", "ACT07", "ACT08", "ACT09", "WIDE", "ACT12"].contains($0.key) }
}

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }

    /// 0xRRGGBB in sRGB, or nil for a color that has no such form.
    var rgb: UInt32? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func part(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return part(color.redComponent) << 16 | part(color.greenComponent) << 8 | part(color.blueComponent)
    }
}

/// What is printed on one of the lower keys.
enum KeyFace: Equatable {
    case symbol(String)
    case text(String)
    case blank
}

/// The pad from above, as a plan of its controls: dark keys with a picture, grey Agent Keys with
/// a dot of light, the dial top left, the stick top right, the layer button bottom left. It is
/// dark in a light window too.
struct PadDrawing: View {
    var slots: [AgentStatus]
    var pulsing: Set<Int> = []
    /// The Agent Keys whose sessions are pinned.
    var pinned: Set<Int> = []
    /// The Agent Keys whose light is dim: on Orca's layer, a key whose chat is closed.
    var dim: Set<Int> = []
    var color: (AgentStatus) -> Color
    /// What to print on each of the lower keys, by the key's name in the file.
    var faces: [String: KeyFace] = [:]
    /// What each lower key runs, in words, by the key's name in the file. A key's picture says
    /// nothing to a screen reader, and its stock name ("Close" for a cross) says the wrong thing.
    var names: [String: String] = [:]
    var selection: PadControl?
    /// False where the drawing shows the layout and not what the pad is doing: the Agent Keys are
    /// then all drawn as plain grey caps.
    var showsLights = true
    /// The side of one key.
    var unit: CGFloat = 50
    var tapped: (PadControl, Int?) -> Void = { _, _ in }

    private var gap: CGFloat { unit * 0.075 }

    /// One place on the pad.
    enum Spot: Equatable {
        case dial, stick, layerButton
        case agent(Int)
        /// A lower key, and how many places wide it is.
        case key(String, wide: Int)
    }

    /// The pad as it is built, row by row from the top.
    static let rows: [[Spot]] = [
        [.dial, .agent(0), .agent(1), .stick],
        [.agent(2), .agent(3), .agent(4), .agent(5)],
        [.key("ACT06", wide: 1), .key("ACT07", wide: 1), .key("ACT08", wide: 1), .key("ACT09", wide: 1)],
        [.layerButton, .key("WIDE", wide: 2), .key("ACT12", wide: 1)],
    ]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.24, style: .continuous)
        VStack(spacing: gap) {
            ForEach(0 ..< Self.rows.count, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0 ..< Self.rows[row].count, id: \.self) { column in
                        spot(Self.rows[row][column])
                    }
                }
            }
        }
        .padding(unit * 0.19)
        .background(shape.fill(PadColors.body).shadow(color: Color.white.opacity(0.07), radius: unit * 0.7))
        .overlay(shape.strokeBorder(PadColors.edge, lineWidth: 1))
    }

    // MARK: The controls

    @ViewBuilder private func spot(_ spot: Spot) -> some View {
        switch spot {
        case .dial: dial
        case .stick: stick
        case .layerButton: layerButton
        case let .agent(slot): agent(slot)
        case let .key(name, wide): key(name, width: unit * CGFloat(wide) + gap * CGFloat(wide - 1))
        }
    }

    private func agent(_ slot: Int) -> some View {
        let status = slots.indices.contains(slot) ? slots[slot] : .off
        let says = showsLights
            ? "Agent Key \(slot + 1): \(status.label)" + (pinned.contains(slot) ? ", pinned" : "") + (dim.contains(slot) ? ", closed" : "")
            : "Agent Key \(slot + 1)"
        return Button {
            tapped(.agents, slot)
        } label: {
            AgentCap(light: status == .off ? nil : color(status).opacity(dim.contains(slot) ? 0.3 : 1),
                     label: "\(slot + 1)", pulsing: pulsing.contains(slot),
                     pinned: pinned.contains(slot), plain: !showsLights, unit: unit)
                .overlay(ring(RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous), on: selection == .agents))
        }
        .buttonStyle(.plain)
        .help(says)
        .accessibilityLabel(says)
    }

    private func key(_ name: String, width: CGFloat? = nil) -> some View {
        let title = PadControl.key(name).title
        let says = names[name].map { "\(title): \($0)" } ?? title
        return Button {
            tapped(.key(name), nil)
        } label: {
            CommandCap(face: faces[name] ?? .blank, unit: unit, width: width)
                .overlay(ring(RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous), on: selection == .key(name)))
        }
        .buttonStyle(.plain)
        .help(says)
        .accessibilityLabel(says)
    }

    /// The line around the control that is being set up, a little outside it.
    private func ring(_ shape: some InsettableShape, on: Bool) -> some View {
        shape.inset(by: -unit * 0.05).strokeBorder(Color.accentColor, lineWidth: max(2, unit * 0.045)).opacity(on ? 1 : 0)
    }

    /// A flat knob, one half in shade.
    private var dial: some View {
        Button {
            tapped(.dial, nil)
        } label: {
            ZStack {
                Circle().fill(PadColors.dial)
                Circle().trim(from: 0, to: 0.5).fill(PadColors.dialShade).rotationEffect(.degrees(135))
            }
            .padding(unit * 0.04)
            .frame(width: unit, height: unit)
            .overlay(ring(Circle(), on: selection == .dial))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Dial")
        .accessibilityLabel("Dial")
    }

    /// A black cap in a square well.
    private var stick: some View {
        let well = RoundedRectangle(cornerRadius: unit * 0.17, style: .continuous)
        return Button {
            tapped(.stick, nil)
        } label: {
            ZStack {
                well.fill(PadColors.well)
                well.strokeBorder(PadColors.keyEdge, lineWidth: 1)
                Circle().fill(Color(rgb: 0x0E0E10)).padding(unit * 0.18)
            }
            .frame(width: unit, height: unit)
            .overlay(ring(RoundedRectangle(cornerRadius: unit * 0.22, style: .continuous), on: selection == .stick))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stick")
        .accessibilityLabel("Stick")
    }

    /// The round button that changes the layer, with the three channel lights beside it. The bridge
    /// reads it and binds nothing to it.
    private var layerButton: some View {
        HStack(spacing: unit * 0.1) {
            VStack(spacing: unit * 0.07) {
                ForEach([UInt32(0xABBCF6), 0x85868C, 0xB6B886], id: \.self) { rgb in
                    Circle().fill(Color(rgb: rgb)).frame(width: unit * 0.075, height: unit * 0.075)
                }
            }
            Circle().fill(PadColors.key).frame(width: unit * 0.62, height: unit * 0.62)
        }
        .frame(width: unit, height: unit)
        .help("The layer button. MicroBridge works on layer 1.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The layer button. MicroBridge works on layer 1.")
    }
}

/// The colors of the plan of the pad. They are the same in a light and a dark window.
enum PadColors {
    static let body = Color(rgb: 0x17191E)
    static let edge = Color(rgb: 0x2E3038)
    static let key = Color(rgb: 0x202126)
    static let keyEdge = Color(rgb: 0x34363F)
    /// The keycap that is picked in the keycap dialog.
    static let keyChosen = Color(rgb: 0x434246)
    static let well = Color(rgb: 0x25262C)
    static let dial = Color(rgb: 0x3B3B44)
    static let dialShade = Color(rgb: 0x282831)
    /// An Agent Key with its light on, and with it off.
    static let cap = Color(rgb: 0x8B8B8D)
    static let capOff = Color(rgb: 0x383A42)
}

/// An Agent Key: a grey cap with a dot of its light in the middle and the same light around it.
/// `light` is nil for a key with no light on.
struct AgentCap: View {
    var light: Color?
    var label = ""
    var pulsing = false
    var pinned = false
    /// A grey cap with no light to tell: for a picture of the layout.
    var plain = false
    /// False for a cap in a list, where the light around it would run into the next row.
    var glows = true
    var unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.17, style: .continuous)
        ZStack {
            if plain {
                shape.fill(PadColors.cap).shadow(color: Color.white.opacity(0.16), radius: unit * 0.12)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0)], startPoint: .top,
                                          endPoint: .bottom))
            } else if let light {
                shape.fill(PadColors.cap)
                    .shadow(color: light.opacity(glows ? 0.75 : 0), radius: unit * 0.2)
                    .shadow(color: Color.white.opacity(glows ? 0.18 : 0), radius: unit * 0.08)
                    .modifier(Breathing(on: pulsing))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0)], startPoint: .top,
                                          endPoint: .bottom))
                Circle()
                    .fill(RadialGradient(colors: [light, light.opacity(0.85), light.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: unit * 0.24))
                    .frame(width: unit * 0.5, height: unit * 0.5)
                    .modifier(Breathing(on: pulsing))
            } else {
                shape.fill(PadColors.capOff)
            }
            shape.strokeBorder(Color.white.opacity(light == nil && !plain ? 0.07 : 0.28), lineWidth: 1)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: unit * 0.2, weight: .semibold, design: .rounded))
                    .foregroundStyle(light == nil && !plain ? Color.white.opacity(0.4) : Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, unit * 0.12)
                    .padding(.top, unit * 0.07)
            }
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: unit * 0.16, weight: .semibold))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(light == nil ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(unit * 0.09)
            }
        }
        .frame(width: unit, height: unit)
        .contentShape(shape)
    }
}

/// A dark key with a picture of what it does.
struct CommandCap: View {
    var face: KeyFace
    var unit: CGFloat
    var width: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.17, style: .continuous)
        ZStack {
            shape.fill(PadColors.key)
            shape.strokeBorder(PadColors.keyEdge, lineWidth: 1)
            switch face {
            case let .symbol(name):
                Image(systemName: name).font(.system(size: unit * 0.36, weight: .regular)).foregroundStyle(Color.white.opacity(0.92))
            case let .text(text):
                Text(text)
                    .font(.system(size: unit * 0.2, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, unit * 0.1)
            case .blank:
                EmptyView()
            }
        }
        .frame(width: width ?? unit, height: unit)
        .contentShape(shape)
    }
}

/// Fades a light down and back up, like the pad does for the session on screen.
struct Breathing: ViewModifier {
    var on: Bool

    func body(content: Content) -> some View {
        if on {
            content.phaseAnimator([1.0, 0.4]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 1.2)
            }
        } else {
            content
        }
    }
}
