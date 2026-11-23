import AppKit
import MicroKit
import SwiftUI
import Testing
@testable import MicroUI

/// The action editor as a person uses it: the steps behind its menus and buttons, and real
/// typing into its fields in a window that is never shown. The made-up model writes no file.
@MainActor @Suite struct WindowTypingTests {
    /// The rows of one list as the window would draw them now.
    private func rows(_ model: BridgeModel, _ state: WindowState, _ list: ActionList) -> ActionRows {
        ActionRows(model: model, state: state, list: list, title: "", actions: model.actions(in: list), emptyNote: "")
    }

    @Test func aRowIsAddedTypedSavedMovedAndRemoved() {
        let model = BridgeModel(demo: true)
        let state = WindowState()
        let list = ActionList(owner: .section("agentKeys"), trigger: "doubleTap")
        let typed = list.id + "#1"

        // A kind that is one word is saved as soon as it is picked.
        rows(model, state, list).add(.pin)
        #expect(model.actions(in: list) == ["pin"])
        #expect(state.drafts.isEmpty)
        #expect(state.opened.contains(list.id))

        // A kind that needs words waits for them.
        rows(model, state, list).add(.key)
        #expect(state.drafts[typed] == ActionDraft(kind: .key))
        #expect(model.actions(in: list) == ["pin"])
        rows(model, state, list).change(to: ActionDraft(kind: .key, value: "cmd+"), at: 1, saveNow: false)
        rows(model, state, list).commit(1)
        #expect(model.actions(in: list) == ["pin"])
        #expect(state.drafts[typed] == ActionDraft(kind: .key, value: "cmd+"))
        rows(model, state, list).change(to: ActionDraft(kind: .key, value: "cmd+k"), at: 1, saveNow: false)
        #expect(model.actions(in: list) == ["pin"])
        rows(model, state, list).commit(1)
        #expect(model.actions(in: list) == ["pin", "key:cmd+k"])
        #expect(state.drafts.isEmpty)
        #expect(model.does("AG", "doubleTap").claude == [.pin, Action.parse("key:cmd+k")])

        // Another way to press the same key is saved at once; a kind with nothing in it is not.
        rows(model, state, list).setKind(.keyDown, at: 1)
        #expect(model.actions(in: list) == ["pin", "keydown:cmd+k"])
        rows(model, state, list).setKind(.text, at: 1)
        #expect(state.drafts[typed] == ActionDraft(kind: .text))
        #expect(model.actions(in: list) == ["pin", "keydown:cmd+k"])
        // Typing the saved action back leaves nothing to save.
        rows(model, state, list).change(to: ActionDraft(kind: .keyDown, value: "cmd+k"), at: 1, saveNow: false)
        #expect(state.drafts.isEmpty)

        rows(model, state, list).move(1, by: -1)
        #expect(model.actions(in: list) == ["keydown:cmd+k", "pin"])
        rows(model, state, list).move(0, by: -1)
        rows(model, state, list).move(1, by: 1)
        #expect(model.actions(in: list) == ["keydown:cmd+k", "pin"])
        rows(model, state, list).remove(0)
        rows(model, state, list).remove(0)
        #expect(model.actions(in: list).isEmpty)
        #expect(model.trigger("doubleTap", of: "agentKeys") == nil)
        // The other triggers of the Agent Keys are as they were.
        #expect(model.does("AG", "press").claude == [.ack, .jump, .pointerToChat])
        #expect(model.does("AG", "hold").claude == [.forget])
    }

    @Test func textIsSentOrNotWithOneBox() {
        let model = BridgeModel(demo: true)
        let state = WindowState()
        let list = ActionList(owner: .command("FAST", target: "default"), trigger: "press")
        #expect(model.actions(in: list) == ["text:/fast\n"])
        // On a saved row the box is saved at once.
        rows(model, state, list).change(to: ActionDraft(kind: .text, value: "/fast"), at: 0, saveNow: true)
        #expect(model.actions(in: list) == ["text:/fast"])
        #expect(state.drafts.isEmpty)
        // A command cannot run a command, so that row is never saved.
        rows(model, state, list).add(.command)
        rows(model, state, list).change(to: ActionDraft(kind: .command, value: "APPR"), at: 1, saveNow: true)
        rows(model, state, list).commit(1)
        #expect(model.actions(in: list) == ["text:/fast"])
        #expect(model.notice == nil)
    }

    // MARK: The window

    /// A window needs a login session with a screen, which a bare build machine may not have.
    nonisolated static var hasScreen: Bool { CGSessionCopyCurrentDictionary() != nil }

    private func fields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField, field.isEditable { found.append(field) }
        for child in view.subviews { found += fields(in: child) }
        return found
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    private func window(_ model: BridgeModel, _ state: WindowState) -> (NSWindow, NSView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: MicroApp.windowSize), styleMask: MicroApp.windowStyle,
                              backing: .buffered, defer: false)
        let host = NSHostingView(rootView: RootView(model: model, state: state))
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.setContentSize(MicroApp.windowSize)
        host.layoutSubtreeIfNeeded()
        settle()
        return (window, host)
    }

    /// Replaces what a field holds, the way typing over a selection does.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        let focused = window.makeFirstResponder(field)
        #expect(focused)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        settle()
    }

    private func pressReturn(in field: NSTextField) throws {
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        settle()
    }

    @Test(.enabled(if: hasScreen)) func typingInAFieldWaitsForReturn() throws {
        let model = BridgeModel(demo: true)
        let press = ActionList(owner: .key("ACT09"), trigger: "press")
        model.setActions(["key:cmd+b"], in: press)
        let state = WindowState(tab: .keys, selection: .key("ACT09"))
        let (window, host) = window(model, state)

        let field = try #require(fields(in: host).first { $0.stringValue == "cmd+b" })
        try type("cmd+", into: field, in: window)
        #expect(state.drafts[press.id + "#0"] == ActionDraft(kind: .key, value: "cmd+"))
        #expect(model.actions(in: press) == ["key:cmd+b"])
        // Return on half a key saves nothing.
        try pressReturn(in: field)
        #expect(model.actions(in: press) == ["key:cmd+b"])
        #expect(state.drafts[press.id + "#0"] == ActionDraft(kind: .key, value: "cmd+"))

        let again = try #require(fields(in: host).first { $0.stringValue == "cmd+" })
        try type("cmd+k", into: again, in: window)
        #expect(model.actions(in: press) == ["key:cmd+b"])
        try pressReturn(in: again)
        #expect(model.actions(in: press) == ["key:cmd+k"])
        #expect(state.drafts.isEmpty)
        #expect(model.does("ACT09", "press").claude == [Action.parse("key:cmd+k")])
        #expect(fields(in: host).contains { $0.stringValue == "cmd+k" })
        withExtendedLifetime(window) {}
    }

    @Test(.enabled(if: hasScreen)) func theKeycapDialogSearchesAsYouType() throws {
        let model = BridgeModel(demo: true)
        let state = WindowState(tab: .keys, selection: .key("ACT07"))
        // The dialog is not in the window until a key opens it.
        let (closed, closedHost) = window(model, state)
        #expect(!fields(in: closedHost).contains { $0.placeholderString == "Search commands" })
        withExtendedLifetime(closed) {}

        state.editKeycap("ACT07", current: model.keycap("ACT07").cap)
        let (window, host) = window(model, state)
        let search = try #require(fields(in: host).first { $0.placeholderString == "Search commands" })
        try type("decl", into: search, in: window)
        #expect(state.keycapSearch == "decl")
        #expect(KeycapDialog(model: model, state: state, key: "ACT07").names == ["REJ"])
        // Typing in the search box picks nothing and saves nothing.
        #expect(state.keycapDraft == .command("APPR"))
        #expect(model.keycap("ACT07").isDefault)
        withExtendedLifetime(window) {}
    }

    @Test(.enabled(if: hasScreen)) func aNewCommandIsNamedInItsField() throws {
        let model = BridgeModel(demo: true)
        let state = WindowState(tab: .commands)
        let (window, host) = window(model, state)

        let name = try #require(fields(in: host).first { $0.placeholderString == "New command" })
        try type("two words", into: name, in: window)
        try pressReturn(in: name)
        #expect(state.newCommandProblem == "A name is 1 to 24 letters, digits, + - or _.")
        #expect(model.config.commands["TWO WORDS"] == nil)

        try type("notes", into: name, in: window)
        try pressReturn(in: name)
        #expect(state.newCommandProblem == nil)
        #expect(model.config.commands["NOTES"] != nil)
        #expect(state.command == "NOTES")
        #expect(state.newCommand.isEmpty)
        withExtendedLifetime(window) {}
    }
}
