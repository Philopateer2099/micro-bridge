import AppKit
import MicroKit
import SwiftUI

/// The MicroBridge window. It is a client of the daemon: it asks for the state over the socket
/// and changes the config file, which the daemon picks up within a second.
public enum MicroApp {
    @MainActor private static var delegate: AppDelegate?

    /// Shows the window and runs until the person quits. `demo` shows made-up sessions and
    /// writes nothing.
    @MainActor public static func run(demo: Bool = false) -> Never {
        let app = NSApplication.shared
        let delegate = AppDelegate(model: BridgeModel(demo: demo))
        self.delegate = delegate
        app.delegate = delegate
        // The bundle is a background app for the daemon's sake; the window asks for a Dock icon.
        app.setActivationPolicy(.regular)
        app.applicationIconImage = icon(side: 256)
        app.mainMenu = delegate.menu()
        app.run()
        exit(0)
    }

    static let windowSize = NSSize(width: 1080, height: 800)
    static let windowStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

    /// Draws every screen into PNG files in `directory`, without showing a window, for checking
    /// the layout while developing. The sessions are made up, or with `live` they are what the
    /// bridge and the config file say right now.
    @MainActor public static func snapshot(to directory: String, live: Bool = false, size: CGSize? = nil) throws {
        let windowSize = size ?? windowSize
        _ = NSApplication.shared
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func write(_ name: String, dark: Bool, _ view: some View) throws {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: windowStyle,
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: view)
            host.sizingOptions = [.minSize]
            window.contentView = host
            window.setContentSize(windowSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            // The picture comes in the display's own colors. sRGB reads the same everywhere.
            let portable = bitmap.converting(to: .sRGB, renderingIntent: .default) ?? bitmap
            guard let png = portable.representation(using: .png, properties: [:]) else { return }
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            print(name + ".png")
        }
        func screen(_ tab: Tab, _ selection: PadControl = .key("ACT07"), model: BridgeModel? = nil) -> some View {
            RootView(model: model ?? BridgeModel(demo: true), state: WindowState(tab: tab, selection: selection))
        }
        if live {
            let model = BridgeModel()
            model.refresh()
            // The bridge answers on another thread; give it time to.
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            for tab in Tab.allCases { try write("live-" + tab.rawValue, dark: true, screen(tab, model: model)) }
            return
        }
        for tab in Tab.allCases { try write(tab.rawValue, dark: true, screen(tab)) }
        try write("pad-light", dark: false, screen(.pad))
        try write("lights-light", dark: false, screen(.lights))
        for control in [PadControl.agents, .dial, .stick] {
            try write("keys-" + control.fileName, dark: true, screen(.keys, control))
        }
        // A key with its own actions, with one action half typed and one being added.
        let edited = BridgeModel(demo: true)
        let press = ActionList(owner: .key("ACT09"), trigger: "press")
        edited.setActions(["cmd:SPLIT", "key:cmd+b", "text:/compact\n"], in: press)
        edited.setActions(["click:Suggested next actions/first", "sh:say done"], in: ActionList(owner: .key("ACT09"), trigger: "hold"))
        let typing = WindowState(tab: .keys, selection: .key("ACT09"))
        typing.drafts[press.id + "#1"] = ActionDraft(kind: .key, value: "cmd+")
        typing.drafts[press.id + "#3"] = ActionDraft(kind: .open)
        try write("keys-own", dark: true, RootView(model: edited, state: typing))
        try write("keys-own-light", dark: false, RootView(model: edited, state: typing))
        // The keycap dialog, with a keycap picked that is not saved yet.
        let picking = WindowState(tab: .keys, selection: .key("ACT07"))
        picking.editKeycap("ACT07", current: .command("APPR"))
        picking.keycapDraft = .command("PLAN")
        try write("keys-keycap", dark: true, RootView(model: BridgeModel(demo: true), state: picking))
        try write("keys-keycap-light", dark: false, RootView(model: BridgeModel(demo: true), state: picking))
        let made = BridgeModel(demo: true)
        _ = made.addCommand("NOTES")
        made.setActions(["open:/System/Applications/Notes.app"], in: ActionList(owner: .command("NOTES", target: "default"), trigger: "press"))
        try write("commands-yours", dark: true,
                  RootView(model: made, state: WindowState(tab: .commands, command: "NOTES")))
        try write("commands-mic", dark: false,
                  RootView(model: BridgeModel(demo: true), state: WindowState(tab: .commands, command: "MIC")))
        // Orca has a layer of its own, and the pad is on it.
        let orca = BridgeModel(demo: true)
        orca.showOrca(padThere: true)
        try write("pad-orca", dark: true, screen(.pad, model: orca))
        try write("behavior-orca", dark: true, screen(.behavior, model: orca))
        let stopped = BridgeModel(demo: true)
        stopped.showStopped()
        try write("setup-stopped", dark: true, screen(.setup, model: stopped))
        try writeIcon(to: directory + "/icon.png", side: 512)
        print("icon.png")
    }

    /// The app's icon as a PNG file, for the bundle.
    @MainActor public static func writeIcon(to path: String, side: CGFloat = 1024) throws {
        let image = icon(side: side)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: path))
    }

    @MainActor static func icon(side: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: AppIcon(side: side))
        renderer.scale = 1
        return renderer.nsImage ?? NSImage(size: NSSize(width: side, height: side))
    }
}

/// The pad from above with its lights on, over a dark tile.
struct AppIcon: View {
    var side: CGFloat

    var body: some View {
        let tile = side * 0.82
        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(rgb: 0x2A2D33), Color(rgb: 0x0B0C0E)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, side / 256))
            PadMark(side: tile * 0.74).shadow(color: Color.white.opacity(0.28), radius: tile * 0.06)
        }
        .frame(width: tile, height: tile)
        .frame(width: side, height: side)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: BridgeModel
    private let state = WindowState()
    private var window: NSWindow?

    init(model: BridgeModel) {
        self.model = model
    }

    func applicationDidFinishLaunching(_: Notification) {
        model.start()
        showWindow()
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showWindow()
        return true
    }

    /// The window is the whole app. The bridge is another process and keeps running.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }

    func applicationWillTerminate(_: Notification) {
        model.save()
    }

    private func showWindow() {
        if window == nil {
            let made = NSWindow(contentRect: NSRect(origin: .zero, size: MicroApp.windowSize),
                                styleMask: MicroApp.windowStyle, backing: .buffered, defer: false)
            made.title = "MicroBridge"
            made.titlebarAppearsTransparent = true
            made.titleVisibility = .hidden
            made.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: RootView(model: model, state: state))
            // The view sets the smallest size only. Left alone it also sets the window's size
            // to fit the longest screen.
            host.sizingOptions = [.minSize]
            made.contentView = host
            made.setContentSize(MicroApp.windowSize)
            made.center()
            made.setFrameAutosaveName("MicroBridge window")
            window = made
        }
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func about(_: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "MicroBridge",
            .applicationVersion: version ?? "development build",
            .version: "",
            .credits: NSAttributedString(
                string: "Drives the Codex Micro keypad from Claude Code.\n"
                    + "Unofficial. Not affiliated with OpenAI, Work Louder or Anthropic.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    func menu() -> NSMenu {
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                  target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            return holder
        }
        let main = NSMenu()
        main.addItem(submenu("MicroBridge", [
            item("About MicroBridge", #selector(about(_:)), target: self),
            .separator(),
            item("Hide MicroBridge", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit MicroBridge", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        let windows = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        main.addItem(windows)
        NSApp.windowsMenu = windows.submenu
        return main
    }
}
