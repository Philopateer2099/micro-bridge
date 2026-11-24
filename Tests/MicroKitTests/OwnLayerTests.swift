import Foundation
@testable import MicroKit
import Testing

/// A second layer the bridge drives itself, for an app that does not drive the pad (Orca), and
/// the rule that keeps the layers apart: a layer's controls do nothing in another layer's app.
@MainActor
struct OwnLayerTests {
    static let blue = Int(AgentStatus.working.color)
    static let orcaOnLayerTwo = #""apps": {"orca": ["com.stablyai.orca"]}, "layerApps": {"2": ["orca"]},"#

    /// The pad has its keys on layer 2, and the config says that layer is the bridge's, for Orca.
    static func bench(layers: String = "{}", more: String = "", running: Set<String> = [Bench.claude, Bench.orca],
                      helper: Bool = true) throws -> Bench {
        let bench = try Bench(layers: layers, helper: helper, more: orcaOnLayerTwo + more)
        bench.pad.keyLayers = [1, 2]
        bench.scene.running = running
        return bench
    }

    /// The log line that would have explained 2026-11-24 at once: Orca had layer 2, the owner's
    /// file listed the apps the bridge types in, and Orca was not one of them (D-067).
    @Test func theBridgeSaysWhenALayersAppIsLeftOutOfTheTypingList() throws {
        let missing = try Self.bench(more: #""keystrokeApps": ["com.anthropic.claudefordesktop"],"#)
        missing.tick()
        #expect(missing.said("layerApps.2: com.stablyai.orca is not in keystrokeApps"))

        let listed = try Self.bench(more: #""keystrokeApps": ["com.anthropic.claudefordesktop", "com.stablyai.orca"],"#)
        listed.tick()
        #expect(!listed.said("is not in keystrokeApps"))
    }

    @Test func onItsOwnSecondLayerTheBridgeActsAndWarnsOfNothing() throws {
        let bench = try Self.bench()
        bench.scene.front = Bench.orca
        bench.tick()
        bench.tap(to: 2)
        #expect(bench.said("the pad is on layer 2, one of the bridge's own: its keys and controls are for com.stablyai.orca"))
        #expect(bench.titles == ["Codex Micro is on layer 2"])
        #expect(bench.scene.notes.last?.text == "Its keys are for Orca.")
        // No mishap: its keys reach the bridge there.
        #expect(!bench.said("Tap its touch sensor"))
        bench.press()
        #expect(bench.acted == 1)

        bench.scene.front = Bench.claude
        bench.tap(to: 1)
        #expect(bench.said("the pad is on layer 1, one of the bridge's own"))
        #expect(bench.titles == ["Codex Micro is on layer 2", "Codex Micro is on layer 1"])
        #expect(bench.scene.notes.last?.text == "Its keys are for Claude and com.apple.Terminal.")
        bench.press()
        #expect(bench.acted == 2)
    }

    /// The pad was on that layer already: it is said in the log, and nobody is notified.
    @Test func aPadThatStartsOnTheSecondLayerIsTheBridgesThere() throws {
        let bench = try Self.bench()
        bench.scene.front = Bench.orca
        bench.pad.layer = 2
        bench.tick()
        #expect(bench.said("the pad is on layer 2, one of the bridge's own"))
        #expect(bench.titles.isEmpty)
        bench.press()
        #expect(bench.acted == 1)
    }

    @Test func withLayerWarningOffALayerChangeIsOnlyInTheLog() throws {
        let bench = try Self.bench(more: #""layerWarning": false,"#)
        bench.tick()
        bench.tap(to: 2)
        #expect(bench.said("the pad is on layer 2, one of the bridge's own"))
        #expect(bench.titles.isEmpty)
    }

    /// ChatGPT runs behind and must not hear the keys of either of the bridge's layers.
    @Test func theBridgeHoldsThePadOnItsSecondLayerToo() throws {
        let bench = try Self.bench(running: [Bench.claude, Bench.orca, Bench.chatGPT])
        bench.tick()
        #expect(bench.pad.held)
        bench.tap(to: 2)
        #expect(bench.pad.held)
        #expect(!bench.pad.heard.contains("share"))
    }

    /// The first press after a tap must go by the right layer: the tap is seen within the
    /// second, without waiting for the next one.
    @Test func aTapToTheSecondLayerIsSeenWithinTheSecond() async throws {
        let bench = try Self.bench()
        bench.scene.front = Bench.claude
        bench.tick()
        bench.pad.layer = 2
        await bench.wait { bench.said("the pad is on layer 2, one of the bridge's own") }
        #expect(bench.said("the pad is on layer 2, one of the bridge's own"))
        await bench.idle()
        bench.press()
        #expect(bench.acted == 0)
    }

    // MARK: Its keys

    /// The six keys of the second layer are its own. The sessions on the first layer's keys
    /// show there only.
    @Test func theSecondLayersKeysDoNotShowTheFirstLayersSessions() throws {
        let bench = try Self.bench()
        bench.tick()
        try bench.say(#"{"op":"report","session":"one","status":"working"}"#)
        #expect(bench.pad.keyColors == [Self.blue, 0, 0, 0, 0, 0])

        bench.tap(to: 2)
        #expect(bench.pad.keyColors == [0, 0, 0, 0, 0, 0])
        // A session that reports meanwhile lights nothing here.
        try bench.say(#"{"op":"report","session":"two","status":"working"}"#)
        #expect(bench.pad.keyColors == [0, 0, 0, 0, 0, 0])

        bench.tap(to: 1)
        #expect(bench.pad.keyColors == [Self.blue, Self.blue, 0, 0, 0, 0])
    }

    /// A press of a key on the second layer is not a press of the session that has that key
    /// on the first.
    @Test func aKeyOfTheSecondLayerDoesNotActOnTheFirstLayersSession() throws {
        let bench = try Self.bench(more: #""agentKeys": {"press": "ack"},"#)
        bench.tick()
        try bench.say(#"{"op":"report","session":"one","status":"done"}"#)
        #expect(bench.pad.keyColors?.first == Int(AgentStatus.done.color))

        bench.tap(to: 2)
        bench.pad.press("AG00")
        #expect(bench.said("AG.press key 1 on layer 2: no chat on this key"))
        #expect(!bench.said("AG.press key 1 in "))
        bench.tap(to: 1)
        // Still done and unread.
        #expect(bench.pad.keyColors?.first == Int(AgentStatus.done.color))

        bench.pad.press("AG00")
        #expect(bench.said("AG.press key 1 in "))
        #expect(bench.pad.keyColors?.first == Int(AgentStatus.idle.color))
    }

    /// The pad goes to sleep on the second layer and wakes there: its keys are still that
    /// layer's, not the first one's sessions.
    @Test func aPadThatComesBackOnTheSecondLayerShowsItsKeys() async throws {
        let bench = try Self.bench()
        bench.tick()
        try bench.say(#"{"op":"report","session":"one","status":"working"}"#)
        bench.tap(to: 2)
        #expect(bench.pad.keyColors == [0, 0, 0, 0, 0, 0])

        bench.pad.onGone?()
        await bench.wait { bench.said("pad disconnected") }
        await bench.idle()
        bench.tick()
        #expect(bench.scene.lines.filter { $0.hasPrefix("pad connected") }.count == 2)
        bench.tick()
        #expect(bench.pad.keyColors == [0, 0, 0, 0, 0, 0])
        // Nobody tapped: no second notification.
        #expect(bench.titles == ["Codex Micro is on layer 2"])
        bench.tap(to: 1)
        #expect(bench.pad.keyColors == [Self.blue, 0, 0, 0, 0, 0])
    }

    // MARK: Layers are isolated

    /// On Claude's layer the controls do nothing in Orca, on Orca's layer nothing in the Claude
    /// app or a terminal. In an app that is neither they act on both layers.
    @Test func aLayersControlsDoNothingInAnAppOfAnotherLayer() throws {
        let bench = try Self.bench()
        bench.tick()
        var expected = 0
        for (layer, app, acts) in [
            (1, Bench.claude, true), (1, "com.mitchellh.ghostty", true), (1, Bench.orca, false), (1, Bench.safari, true),
            (2, Bench.orca, true), (2, Bench.claude, false), (2, "com.mitchellh.ghostty", false), (2, Bench.safari, true),
        ] {
            bench.scene.front = app
            bench.tap(to: layer)
            bench.press()
            if acts { expected += 1 }
            #expect(bench.acted == expected, "layer \(layer), \(app) in front")
        }
        #expect(bench.said("ACT06.press does nothing: com.stablyai.orca is layer 2's and the pad is on layer 1"))
        #expect(bench.said("ACT06.press does nothing: com.anthropic.claudefordesktop is layer 1's and the pad is on layer 2"))
    }

    /// The app nothing is in front of, as at the login window, belongs to no layer.
    @Test func withNothingInFrontTheControlsAct() throws {
        let bench = try Self.bench()
        bench.scene.front = nil
        bench.tick()
        bench.tap(to: 2)
        bench.press()
        #expect(bench.acted == 1)
    }

    /// An Agent Key brings its own app to the front, so it acts whatever is in front.
    @Test func anAgentKeyActsWhileAnotherLayersAppIsInFront() throws {
        let bench = try Self.bench(more: #""agentKeys": {"press": "ack"},"#)
        bench.scene.front = Bench.orca
        bench.tick()
        try bench.say(#"{"op":"report","session":"one","status":"done"}"#)
        bench.pad.press("AG00")
        #expect(bench.said("AG.press key 1 in com.stablyai.orca: ack"))
        #expect(bench.pad.keyColors?.first == Int(AgentStatus.idle.color))
        // The key next to it does nothing there.
        bench.press()
        #expect(bench.acted == 0)
    }

    /// Without a second layer of its own the bridge keeps nothing apart: Orca is one more app.
    @Test func withoutASecondLayerNothingIsKeptApart() throws {
        let bench = try Bench(layers: "{}", more: #""apps": {"orca": ["com.stablyai.orca"]},"#)
        bench.scene.running = [Bench.claude, Bench.orca]
        bench.scene.front = Bench.orca
        bench.tick()
        bench.press()
        #expect(bench.acted == 1)
        #expect(!bench.said("does nothing"))
    }

    /// The stick scrolls while it is pushed. In another layer's app it scrolls nothing, and a
    /// web page scrolls on both layers.
    @Test func theStickScrollsNothingInAnAppOfAnotherLayer() async throws {
        let bench = try Self.bench(more: #""stick": {"up": "scroll:up", "down": "scroll:down"},"#)
        bench.tick()
        for (layer, app, scrolls) in [
            (1, Bench.orca, false), (1, Bench.safari, true), (1, Bench.claude, true),
            (2, Bench.claude, false), (2, Bench.safari, true), (2, Bench.orca, true),
        ] {
            bench.scene.front = app
            bench.tap(to: layer)
            bench.scene.scrolled = 0
            bench.pad.push(angle: 0.75, distance: 1)
            if scrolls {
                await bench.wait { bench.scene.scrolled > 0 }
            } else {
                try await Task.sleep(for: .milliseconds(120))
            }
            #expect((bench.scene.scrolled > 0) == scrolls, "layer \(layer), \(app) in front")
            bench.pad.push(angle: 0.75, distance: 0)
            await bench.idle()
        }
    }

    /// A push that scrolls a page ends when the layer changes under it.
    @Test func aPushEndsWhenTheLayerChanges() async throws {
        let bench = try Self.bench(more: #""stick": {"up": "scroll:up", "down": "scroll:down"},"#)
        bench.scene.front = Bench.claude
        bench.tick()
        bench.pad.push(angle: 0.75, distance: 1)
        await bench.wait { bench.scene.scrolled > 0 }
        await bench.idle()
        bench.tap(to: 2)
        #expect(bench.said("the pad changed layer"))
        let before = bench.scene.scrolled
        try await Task.sleep(for: .milliseconds(120))
        #expect(bench.scene.scrolled == before)
    }

    // MARK: With ChatGPT on the third layer

    /// Layer 1 is Claude's, layer 2 Orca's, layer 3 ChatGPT's: one tap moves on, and the layer
    /// says who has the pad and whose keys they are.
    @Test func threeLayersEachWithItsOwner() throws {
        let bench = try Self.bench(layers: #"{"3": "com.openai.codex"}"#, more: #""layerKeys": true,"#,
                                   running: [Bench.claude, Bench.orca, Bench.chatGPT])
        bench.pad.keyLayers = [1, 2, 3]
        bench.scene.front = Bench.safari
        bench.tick()
        try bench.say(#"{"op":"report","session":"one","status":"working"}"#)
        bench.press()
        #expect(bench.acted == 1)

        bench.tap(to: 2)
        #expect(bench.pad.held)
        #expect(bench.pad.keyColors == [0, 0, 0, 0, 0, 0])
        bench.press()
        #expect(bench.acted == 2)

        bench.tap(to: 3)
        #expect(!bench.pad.held)
        #expect(bench.said("the pad is on layer 3: the bridge leaves the pad to com.openai.codex"))
        bench.press()
        #expect(bench.acted == 2)

        bench.tap(to: 1)
        #expect(bench.pad.held)
        #expect(bench.pad.keyColors == [Self.blue, 0, 0, 0, 0, 0])
        bench.press()
        #expect(bench.acted == 3)
        // Each change is said once, by the one that knows it.
        #expect(bench.titles == ["Codex Micro is on layer 2", "ChatGPT has the pad", "MicroBridge has the pad"])
    }

    /// ChatGPT's layer before Orca's: leaving it for a layer of the bridge's own is one change,
    /// said once.
    @Test func withAnAppsLayerBeforeTheBridgesOwnEachChangeIsSaidOnce() throws {
        let bench = try Bench(layers: #"{"2": "com.openai.codex"}"#,
                              more: #""layerKeys": true, "layerApps": {"3": ["com.stablyai.orca"]},"#)
        bench.pad.keyLayers = [1, 2, 3]
        bench.scene.running = [Bench.claude, Bench.orca, Bench.chatGPT]
        bench.scene.front = Bench.orca
        bench.tick()
        bench.press()
        #expect(bench.acted == 0)

        bench.tap(to: 2)
        bench.tap(to: 3)
        #expect(bench.titles == ["ChatGPT has the pad", "MicroBridge has the pad"])
        #expect(bench.scene.notes.last?.text == "The pad is on layer 3.")
        #expect(bench.said("the pad is on layer 3, one of the bridge's own"))
        bench.press()
        #expect(bench.acted == 1)

        bench.tap(to: 1)
        #expect(bench.titles.last == "Codex Micro is on layer 1")
        bench.press()
        #expect(bench.acted == 1)
    }
}
