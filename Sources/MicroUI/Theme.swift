import AppKit
import SwiftUI

/// The window's own colors, one set for the dark and one for the light.
enum Theme {
    private static func pair(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }

    static let window = pair(dark: 0x181818, light: 0xFFFFFF)
    static let sidebar = pair(dark: 0x1D1D1D, light: 0xF7F7F8)
    static let card = pair(dark: 0x232323, light: 0xF7F7F8)
    /// A line between two things, and around a card.
    static let line = pair(dark: 0x2D2D2D, light: 0xE4E4E7)
    /// What the sidebar and the lists put behind the thing that is chosen.
    static let chosen = pair(dark: 0x2F2F2F, light: 0xE9E9EC)
    /// A dialog over the window.
    static let dialog = pair(dark: 0x2C2C2C, light: 0xFFFFFF)
}

/// The wide card with the pad in the middle of it.
struct PadCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 14) { content }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(shape.fill(Theme.card))
            .overlay(shape.strokeBorder(Theme.line))
    }
}

/// A small rounded label: a fact about the pad, or a mark on a setting.
struct Chip: View {
    var symbol: String?
    var text: String
    var tint: Color?

    init(_ text: String, symbol: String? = nil, tint: Color? = nil) {
        self.text = text
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(tint ?? Color.primary.opacity(0.8))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill((tint ?? Color.primary).opacity(0.1)))
        .overlay(Capsule().strokeBorder((tint ?? Color.primary).opacity(0.14)))
        .fixedSize()
    }
}

/// The pad very small: the mark beside the app's name, and the picture in the app's icon.
struct PadMark: View {
    var side: CGFloat

    private static let lights: [UInt32?] = [0x304FFE, 0xFF6D00, 0x00E05A, nil, 0xFF0033, 0x304FFE]

    var body: some View {
        let inset = side * 0.075
        let plate = side - inset * 2
        let gap = plate * 0.055
        let edge = plate * 0.115
        let cell = (plate - edge * 2 - gap * 3) / 4
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: 0xEEF1F3), Color(rgb: 0xBEC5CA)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: side * 0.19, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(rgb: 0xE4E8E6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(inset)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    Circle().fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.62)], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: max(0.5, side / 180)))
                        .frame(width: cell, height: cell)
                    agent(0, cell)
                    agent(1, cell)
                    Circle().fill(Color(white: 0.08)).padding(cell * 0.08).frame(width: cell, height: cell)
                }
                HStack(spacing: gap) {
                    ForEach(2 ..< 6, id: \.self) { agent($0, cell) }
                }
                HStack(spacing: gap) {
                    ForEach(0 ..< 4, id: \.self) { _ in key(cell, cell) }
                }
                HStack(spacing: gap) {
                    Circle().fill(Color(white: 0.08)).padding(cell * 0.16).frame(width: cell, height: cell)
                    key(cell * 2 + gap, cell)
                    key(cell, cell)
                }
            }
        }
        .frame(width: side, height: side)
    }

    private func agent(_ slot: Int, _ cell: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
        return ZStack {
            shape.fill(Color(rgb: 0xD5DAD8))
            if let rgb = Self.lights[slot] {
                shape.fill(RadialGradient(colors: [Color(rgb: rgb), Color(rgb: rgb).opacity(0.55)], center: .center,
                                          startRadius: 0, endRadius: cell * 0.72))
            }
        }
        .frame(width: cell, height: cell)
    }

    private func key(_ width: CGFloat, _ cell: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.16), lineWidth: max(0.5, cell * 0.05)))
            .frame(width: width, height: cell)
    }
}
