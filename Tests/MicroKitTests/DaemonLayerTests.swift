import Foundation
import IOKit
@testable import MicroKit
import PadWire
import Testing

/// A pad made of code. It answers requests the way firmware v0.6.1 does, says which layer it
/// is on, and writes down every request and every hold or share in the order they came.
/// Like the real pad it has the Codex keys on layer 1 only: on any other layer a press sends
/// nobody a key message. `keyLayers` puts them on more layers, as Work Louder Input can.
@MainActor
final class FakePad: PadLink {
    var onReport: (([UInt8]) -> Void)?
    var onGone: (() -> Void)?
    let canHold: Bool
    /// What a tap on the touch sensor changes. The pad says nothing when it does.
    var layer = 1
    /// The layers whose keys send key messages.
    var keyLayers: Set<Int> = [1]
    private(set) var held = false
    /// Method names, and "hold" or "share", oldest first.
    private(set) var heard: [String] = []
    private(set) var requests: [String] = []
    /// How many times the bridge has to look before an answer is there. A real pad takes a
    /// few milliseconds, and things happen in them.
    var slowness = 0
    /// Runs once while the bridge waits for an answer.
    var meanwhile: (() -> Void)?
    private var waiting: [[UInt8]] = []
    private var stalled = 0

    init(canHold: Bool) { self.canHold = canHold }

    func start() {}
    func close() {}

    func write(_ request: String) throws(PadError) -> IOReturn {
        guard let object = try? JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any],
              let method = object["method"] as? String, let id = object["id"] as? Int else {
            return kIOReturnBadArgument
        }
        heard.append(method)
        requests.append(request)
        let result = method == Method.status.rawValue
            ? #"{"version":"v0.6.1","profile_index":0,"layer_index":\#(layer),"battery":100,"is_charging":true}"#
            : #"{"ok":1}"#
        waiting += Self.reports(#"{"result":\#(result),"id":\#(id),"method":"\#(method)"}"#)
        stalled = slowness
        return kIOReturnSuccess
    }

    func hold(_ on: Bool) throws(PadError) -> (Bool, IOReturn) {
        heard.append(on ? "hold" : "share")
        held = on
        return (on, kIOReturnSuccess)
    }

    func pump() {
        if stalled > 0 {
            stalled -= 1
            if let now = meanwhile {
                meanwhile = nil
                now()
            }
            return
        }
        while !waiting.isEmpty { onReport?(waiting.removeFirst()) }
    }

    /// A key goes down and comes up. On a layer with the Codex keys the pad says so at once,
    /// also in the middle of an answer. On another layer that key is a keyboard key, and no
    /// message comes.
    func press(_ key: String) {
        guard keyLayers.contains(layer) else { return }
        for action in [1, 0] {
            for report in Self.reports(#"{"method":"v.oai.hid","params":{"k":"\#(key)","act":\#(action)}}"#) { onReport?(report) }
        }
    }

    /// The stick is pushed that far (0…1) toward that angle (0.75 is up), or let go at 0. Like
    /// the keys it says so only on a layer with the Codex keys.
    func push(angle: Double, distance: Double) {
        guard keyLayers.contains(layer) else { return }
        for report in Self.reports(#"{"method":"v.oai.rad","params":{"a":\#(angle),"d":\#(distance)}}"#) { onReport?(report) }
    }

    /// The color of each Agent Key in the last light write, 0 for a key that is off.
    var keyColors: [Int]? {
        guard let last = requests.last(where: { $0.contains(Method.threadsLighting.rawValue) }),
              let object = try? JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any],
              let keys = object["params"] as? [[String: Any]] else { return nil }
        return keys.map { ($0["c"] as? NSNumber)?.intValue ?? -1 }
    }

    private static func reports(_ text: String) -> [[UInt8]] {
        Framing.reports(for: Array((text + "\n").utf8))
    }
}

/// The real `Daemon` on a fake pad, in a scratch folder, with the app in front set by hand.
@MainActor
final class Bench {
    static let chatGPT = PadSharing.chatGPT
    static let claude = "com.anthropic.claudefordesktop"
    static let orca = "com.stablyai.orca"
    static let safari = "com.apple.Safari"

    @MainActor
    final class Scene {
        var front: String? = Bench.claude
        var running: Set<String> = [Bench.chatGPT, Bench.claude]
        var lines: [String] = []
        /// Notifications, each as its title and its text.
        var notes: [(title: String, text: String)] = []
        /// Points the stick has scrolled, up and down added. Nothing on screen moves.
        var scrolled = 0.0
    }

    let scene = Scene()
    let pad: FakePad
    let daemon: Daemon

    /// `layers` is the config's value for that setting, as JSON. `more` is further settings,
    /// each with its comma.
    init(layers: String, helper: Bool = true, more: String = "") throws {
        let directory = NSTemporaryDirectory() + "mb-" + UUID().uuidString.prefix(8)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        // Nothing here types keys or asks an app anything, and notifications land in `scene`.
        // With no session on a key, `ack` does nothing but put the press in the log.
        let config = """
        {
          "lighting": {"offWhenLocked": false, "pulseSelected": false},
          "batteryWarning": 0,
          "layers": \(layers),
          \(more)
          "keys": {"ACT06": "ack"}
        }
        """
        try config.write(toFile: directory + "/config.json", atomically: true, encoding: .utf8)
        let pad = FakePad(canHold: helper)
        self.pad = pad
        let info = PadInfo(productID: 0x8360, model: "Codex Micro", transport: "USB", product: "Codex Micro",
                           usagePairs: [], maxInputReport: 64, maxOutputReport: 64)
        var world = DaemonWorld()
        world.directory = directory
        world.openPad = { () throws(PadError) -> Pad in Pad(link: pad, info: info, note: nil) }
        world.findHelper = { .absent }
        world.frontApp = { [scene] in scene.front }
        world.runningApps = { [scene] in scene.running }
        world.askForAccessibility = {}
        world.notify = { [scene] in scene.notes.append(($0, $1)) }
        world.appName = { [Bench.chatGPT: "ChatGPT", Bench.orca: "Orca", Bench.claude: "Claude"][$0] ?? $0 }
        world.log = { [scene] in scene.lines.append($0) }
        world.scroll = { [scene] in scene.scrolled += abs($0) }
        daemon = try Daemon(world: world)
    }

    /// A pad that has its keys on layer 2 as well, with the setting that says so: one tap
    /// changes who has the pad.
    static func withKeysOnLayerTwo(running: Set<String> = [Bench.chatGPT, Bench.claude], helper: Bool = true) throws -> Bench {
        let bench = try Bench(layers: DaemonLayerTests.layerTwoPassesToChatGPT, helper: helper, more: #""layerKeys": true,"#)
        bench.pad.keyLayers = [1, 2]
        bench.scene.running = running
        return bench
    }

    /// A second passes. A config the daemon turned down would test the defaults instead.
    func tick() {
        daemon.tick()
        #expect(!said("config has problems"))
    }

    /// A tap on the touch sensor and the reading of the next second.
    func tap(to layer: Int) {
        pad.layer = layer
        tick()
    }

    /// A tap to layer 2 and one back, each seen by a reading: one visit.
    func visit() {
        tap(to: 2)
        tap(to: 1)
    }

    func press() {
        pad.press("ACT06")
    }

    /// The daemon waits for each of the pad's answers with the main run loop running, so
    /// after an `await` a test may be inside one of those waits, where a reading of the layer
    /// is skipped. Waits until the daemon is between its conversations with the pad.
    func idle() async {
        await wait { !daemon.isBusy }
    }

    /// What that line does when it comes over the daemon's socket, as from a Claude Code hook
    /// or `micro ctl`.
    func say(_ line: String) throws {
        daemon.take(try Command.parse(line))
    }

    /// Waits up to a second for something the daemon does by its own clock.
    func wait(for done: () -> Bool) async {
        for _ in 0 ..< 100 where !done() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// How many presses the bridge has acted on.
    var acted: Int { scene.lines.filter { $0.hasPrefix("ACT06.press in ") }.count }

    func said(_ text: String) -> Bool { scene.lines.contains { $0.contains(text) } }

    var titles: [String] { scene.notes.map(\.title) }
}

@MainActor
struct DaemonLayerTests {
    static let layerTwoPassesToChatGPT = #"{"2": "com.openai.codex"}"#
    static let sixKeysOff = JSONValue.array((0 ..< 6).map { AgentStatus.off.light(slot: $0).json })

    /// The rule from before layers, on the same bench: the app in front decides.
    @Test func withoutLayersTheAppInFrontDecides() throws {
        let bench = try Bench(layers: "{}")
        bench.scene.front = Bench.chatGPT
        bench.tick()
        #expect(!bench.pad.held)
        bench.press()
        #expect(bench.acted == 0)

        bench.scene.front = Bench.claude
        bench.tick()
        #expect(bench.pad.held)
        bench.press()
        #expect(bench.acted == 1)
    }

    @Test func untilAVisitTheBridgeHoldsThePadAndActsWhateverIsInFront() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.scene.front = Bench.chatGPT
        bench.tick()
        #expect(bench.pad.held)
        bench.press()
        #expect(bench.acted == 1)
        #expect(bench.titles.isEmpty)
    }

    /// An app with a layer is shut out even when `stepAsideFor` does not name it.
    @Test func anAppWithALayerIsShutOutWithoutBeingInStepAsideFor() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT, more: #""stepAsideFor": [],"#)
        bench.scene.front = Bench.chatGPT
        bench.tick()
        #expect(bench.pad.held)
        bench.press()
        #expect(bench.acted == 1)
    }

    @Test func aVisitToTheLayerPassesThePadToItsApp() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.tick()
        #expect(bench.pad.held)

        bench.tap(to: 2)
        // The six Agent Keys off, and only then the other app gets the pad.
        #expect(bench.pad.heard.suffix(2) == [Method.threadsLighting.rawValue, "share"])
        let keys = try #require(bench.pad.requests.last)
        let id = try #require((try JSONSerialization.jsonObject(with: Data(keys.utf8)) as? [String: Any])?["id"] as? Int)
        #expect(keys == RPC.request(.threadsLighting, params: Self.sixKeysOff, id: id))
        // The ring and the backlight are not the bridge's: it could not light them again.
        #expect(!bench.pad.heard.contains(Method.lightingConfig.rawValue))
        #expect(bench.said("a visit to layer 2 passed the pad to com.openai.codex"))
        #expect(bench.titles == ["ChatGPT has the pad"])
        // A visit is no mishap to warn about.
        #expect(!bench.said("Tap its touch sensor"))

        // Back on layer 1, where the keys are, the pad is still that app's.
        let before = bench.pad.heard.count
        bench.tap(to: 1)
        #expect(!bench.pad.held)
        #expect(bench.titles == ["ChatGPT has the pad", "Codex Micro is back on layer 1"])
        #expect(bench.scene.notes.last?.text == "ChatGPT has its keys.")
        bench.press()
        bench.scene.front = Bench.claude
        bench.tick()
        bench.press()
        #expect(bench.acted == 0)
        // No lights from the bridge while the pad is the other app's: it only reads the layer.
        #expect(bench.pad.heard.dropFirst(before).allSatisfy { $0 == Method.status.rawValue })
    }

    @Test func aSecondVisitTakesThePadBack() async throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.scene.front = Bench.chatGPT
        bench.tick()
        bench.visit()
        #expect(!bench.pad.held)

        let before = bench.pad.heard.count
        bench.tap(to: 2)
        #expect(bench.said("a second visit to layer 2 takes the pad back from com.openai.codex"))
        #expect(bench.said("the bridge has the pad back"))
        #expect(bench.titles.last == "MicroBridge has the pad")
        // The key lights it turned off are written again.
        #expect(bench.pad.heard.dropFirst(before).contains(Method.threadsLighting.rawValue))

        // The tap back is seen without waiting for the next second, and the pad is held again
        // before a finger gets from the touch sensor to a key.
        bench.pad.layer = 1
        await bench.wait { bench.pad.held }
        #expect(bench.pad.held)
        #expect(bench.scene.notes.last?.text == "Its keys work again.")
        bench.press()
        #expect(bench.acted == 1)
    }

    @Test func stayingOnTheLayerPassesThePadOnce() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.tick()
        bench.tap(to: 2)
        for _ in 0 ..< 3 { bench.tick() }
        #expect(bench.titles == ["ChatGPT has the pad"])
        bench.tap(to: 1)
        bench.press()
        #expect(bench.acted == 0)
    }

    @Test func anAppThatIsNotOpenDoesNotGetThePad() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.scene.running = [Bench.claude]
        bench.tick()
        bench.visit()
        #expect(bench.said("it is not open: the bridge keeps the pad"))
        #expect(bench.titles == ["ChatGPT is not open", "Codex Micro is back on layer 1"])
        #expect(!bench.pad.heard.contains("share"))
        bench.press()
        #expect(bench.acted == 1)
    }

    @Test func anAppThatQuitsGivesThePadBack() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.tick()
        // The pad stays on layer 2, so nothing but the quit asks for the lights again.
        bench.tap(to: 2)
        #expect(bench.titles == ["ChatGPT has the pad"])

        let before = bench.pad.heard.count
        bench.scene.running = [Bench.claude]
        bench.tick()
        #expect(bench.said("com.openai.codex quit while it had the pad"))
        #expect(bench.titles.last == "MicroBridge has the pad")
        #expect(bench.scene.notes.last?.text == "ChatGPT quit.")
        // The key lights it turned off are written again.
        #expect(bench.pad.heard.dropFirst(before).contains(Method.threadsLighting.rawValue))
        bench.tap(to: 1)
        bench.press()
        #expect(bench.acted == 1)
    }

    /// Nobody tapped: the pad was on that layer already. Its keys are off there, and it says so.
    @Test func thePadOnThatLayerWhenTheBridgeStartsIsNoVisit() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.pad.layer = 2
        bench.tick()
        #expect(bench.titles == ["Codex Micro is on layer 2"])
        #expect(bench.said("Tap its touch sensor"))
        bench.tap(to: 1)
        #expect(bench.pad.held)
        bench.press()
        #expect(bench.acted == 1)
    }

    /// The pad goes to sleep or loses its cable. Who has it is not the pad's to forget.
    @Test func aPadThatComesBackIsStillTheOtherApps() async throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT)
        bench.tick()
        bench.visit()

        bench.pad.onGone?()
        await bench.wait { bench.said("pad disconnected") }
        #expect(bench.said("pad disconnected"))
        let before = bench.pad.heard.count
        bench.tick()
        #expect(bench.scene.lines.filter { $0.hasPrefix("pad connected") }.count == 2)
        bench.tick()
        // It reads the layer again and does nothing else: no lights, no hold.
        #expect(bench.pad.heard.dropFirst(before).contains(Method.status.rawValue))
        #expect(bench.pad.heard.dropFirst(before).allSatisfy { $0 == Method.status.rawValue })
        bench.press()
        #expect(bench.acted == 0)
        // The next visit is a second one.
        bench.tap(to: 2)
        #expect(bench.titles.last == "MicroBridge has the pad")
    }

    @Test func withoutTheHelperAVisitStillSaysWhoActsAndNothingIsHeld() throws {
        let bench = try Bench(layers: Self.layerTwoPassesToChatGPT, helper: false)
        bench.scene.front = Bench.chatGPT
        bench.tick()
        bench.press()
        #expect(bench.acted == 1)

        bench.tap(to: 2)
        // Nothing was held, and the bridge's key lights still go: the keys are the other app's.
        let keys = try #require(bench.pad.requests.last)
        let id = try #require((try JSONSerialization.jsonObject(with: Data(keys.utf8)) as? [String: Any])?["id"] as? Int)
        #expect(keys == RPC.request(.threadsLighting, params: Self.sixKeysOff, id: id))
        bench.tap(to: 1)
        bench.press()
        #expect(bench.acted == 1)

        bench.visit()
        bench.press()
        #expect(bench.acted == 2)
        #expect(!bench.pad.heard.contains("hold"))
        #expect(!bench.pad.heard.contains("share"))
    }

    // MARK: Keys on the layers

    @Test func withKeysOnTheLayerOneTapPassesThePadAndOneTapTakesItBack() throws {
        let bench = try Bench.withKeysOnLayerTwo()
        bench.tick()
        #expect(bench.pad.held)
        bench.press()
        #expect(bench.acted == 1)

        bench.tap(to: 2)
        // The six Agent Keys off, and only then the other app gets the pad.
        #expect(bench.pad.heard.suffix(2) == [Method.threadsLighting.rawValue, "share"])
        let keys = try #require(bench.pad.requests.last)
        let id = try #require((try JSONSerialization.jsonObject(with: Data(keys.utf8)) as? [String: Any])?["id"] as? Int)
        #expect(keys == RPC.request(.threadsLighting, params: Self.sixKeysOff, id: id))
        #expect(bench.said("the pad is on layer 2: the bridge leaves the pad to com.openai.codex"))
        #expect(bench.titles == ["ChatGPT has the pad"])
        #expect(bench.scene.notes.last?.text == "The pad is on layer 2.")
        // The keys work there, so it is no mishap to warn about.
        #expect(!bench.said("Tap its touch sensor"))
        // Those keys are the other app's: the bridge hears them and leaves them.
        bench.press()
        #expect(bench.acted == 1)

        let before = bench.pad.heard.count
        bench.tap(to: 1)
        #expect(bench.pad.held)
        #expect(bench.said("the pad left layer 2: the bridge takes it back from com.openai.codex"))
        // One message says it, not a second one about the layer.
        #expect(bench.titles == ["ChatGPT has the pad", "MicroBridge has the pad"])
        #expect(bench.scene.notes.last?.text == "The pad is on layer 1.")
        // The key lights it turned off are written again.
        #expect(bench.pad.heard.dropFirst(before).contains(Method.threadsLighting.rawValue))
        bench.press()
        #expect(bench.acted == 2)
    }

    /// The pad says nothing when it is tapped, and the first press after a tap must go to the
    /// right app: nobody waits for the next second.
    @Test func withKeysOnTheLayerATapIsSeenWithinTheSecond() async throws {
        let bench = try Bench.withKeysOnLayerTwo()
        bench.tick()
        #expect(bench.pad.held)

        bench.pad.layer = 2
        await bench.wait { !bench.pad.held }
        #expect(!bench.pad.held)
        #expect(bench.titles == ["ChatGPT has the pad"])
        bench.press()
        #expect(bench.acted == 0)

        bench.pad.layer = 1
        await bench.wait { bench.pad.held }
        #expect(bench.pad.held)
        bench.press()
        #expect(bench.acted == 1)
    }

    /// Nobody tapped, and still the layer says who has the pad.
    @Test func withKeysOnTheLayerAPadThatStartsThereIsItsApps() throws {
        let bench = try Bench.withKeysOnLayerTwo()
        bench.pad.layer = 2
        bench.tick()
        #expect(bench.titles == ["ChatGPT has the pad"])
        #expect(!bench.pad.held)
        #expect(!bench.said("Tap its touch sensor"))
        bench.press()
        #expect(bench.acted == 0)
    }

    @Test func withKeysOnTheLayerTheBridgeActsThereWhileItsAppIsNotOpen() throws {
        let bench = try Bench.withKeysOnLayerTwo(running: [Bench.claude])
        bench.tick()
        bench.tap(to: 2)
        #expect(bench.said("the pad is on layer 2, which is com.openai.codex's, but it is not open"))
        #expect(bench.titles == ["ChatGPT is not open"])
        #expect(bench.scene.notes.last?.text == "MicroBridge keeps the pad on layer 2.")
        #expect(!bench.said("Tap its touch sensor"))
        bench.press()
        #expect(bench.acted == 1)
        // Said once.
        bench.tick()
        #expect(bench.titles.count == 1)

        // It opens while the pad is on its layer: it gets the pad without a tap.
        bench.scene.running = [Bench.chatGPT, Bench.claude]
        bench.tick()
        #expect(bench.titles.last == "ChatGPT has the pad")
        bench.press()
        #expect(bench.acted == 1)
    }

    @Test func withKeysOnTheLayerAnAppThatQuitsLeavesItsLayerToTheBridge() throws {
        let bench = try Bench.withKeysOnLayerTwo()
        bench.tick()
        bench.tap(to: 2)
        let before = bench.pad.heard.count
        bench.scene.running = [Bench.claude]
        bench.tick()
        #expect(bench.said("com.openai.codex quit while it had the pad"))
        #expect(bench.titles == ["ChatGPT has the pad", "MicroBridge has the pad"])
        #expect(bench.pad.heard.dropFirst(before).contains(Method.threadsLighting.rawValue))
        // The pad is still on layer 2, and its keys there are the bridge's now.
        bench.press()
        #expect(bench.acted == 1)
        bench.tick()
        #expect(bench.titles.count == 2)
        // Back on layer 1 nothing changed hands, so there is nothing to say.
        bench.tap(to: 1)
        #expect(bench.titles.count == 2)
        bench.press()
        #expect(bench.acted == 2)
    }

    /// Layer 3 has no app and no Codex keys: there the pad is a keyboard, as before.
    @Test func withKeysOnTheLayerALayerWithoutThemStillWarns() throws {
        let bench = try Bench.withKeysOnLayerTwo()
        bench.tick()
        bench.tap(to: 2)
        bench.tap(to: 3)
        #expect(bench.titles == ["ChatGPT has the pad", "MicroBridge has the pad", "Codex Micro is on layer 3"])
        #expect(bench.said("Tap its touch sensor"))
        // A keyboard that is held types nothing.
        #expect(!bench.pad.held)
        bench.tap(to: 1)
        #expect(bench.titles.last == "Codex Micro is back on layer 1")
        #expect(bench.pad.held)
    }

    /// Without the helper nothing is held, and the layer still says who acts and who lights.
    @Test func withKeysOnTheLayerAndNoHelperTheLayerStillSaysWhoActs() throws {
        let bench = try Bench.withKeysOnLayerTwo(helper: false)
        bench.tick()
        bench.tap(to: 2)
        // The bridge's key lights go: on this layer the keys are the other app's.
        let keys = try #require(bench.pad.requests.last)
        let id = try #require((try JSONSerialization.jsonObject(with: Data(keys.utf8)) as? [String: Any])?["id"] as? Int)
        #expect(keys == RPC.request(.threadsLighting, params: Self.sixKeysOff, id: id))
        bench.press()
        #expect(bench.acted == 0)
        bench.tap(to: 1)
        bench.press()
        #expect(bench.acted == 1)
        #expect(!bench.pad.heard.contains("hold"))
        #expect(!bench.pad.heard.contains("share"))
    }
}
