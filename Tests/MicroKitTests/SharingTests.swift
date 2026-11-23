import Foundation
@testable import MicroKit
import Testing

struct PadSharingTests {
    let claude = "com.anthropic.claudefordesktop"

    @Test func stepsAsideWhileChatGPTIsInFront() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        #expect(sharing.front(claude) == nil)
        #expect(sharing.front(PadSharing.chatGPT) == .aside(PadSharing.chatGPT))
        #expect(sharing.front(PadSharing.chatGPT) == nil)
        #expect(sharing.asideFor == PadSharing.chatGPT)
        #expect(sharing.front("com.apple.Terminal") == .back)
        #expect(sharing.asideFor == nil)
        // Nothing in front, as at the login window: the pad is the bridge's.
        _ = sharing.front(PadSharing.chatGPT)
        #expect(sharing.front(nil) == .back)
    }

    @Test func anEmptyListNeverStepsAside() {
        var sharing = PadSharing(apps: [])
        #expect(sharing.front(PadSharing.chatGPT) == nil)
        #expect(sharing.asideFor == nil)
    }

    @Test func paintsOverAnotherAppsLightWriteAtMostOnceASecond() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        #expect(sharing.otherReply(method: "v.oai.thstatus", at: 100) == 0)
        // A repaint is waiting already.
        #expect(sharing.otherReply(method: "v.oai.rgbcfg", at: 100.1) == nil)
        sharing.repainting(at: 100.2)
        let wait = sharing.otherReply(method: "lights.preview", at: 100.5) ?? -1
        #expect(abs(wait - 0.7) < 1e-9)
        sharing.repainting(at: 101.2)
        #expect(sharing.otherReply(method: "v.oai.thstatus", at: 105) == 0)
    }

    @Test func leavesRepliesThatAreNotLightWritesAlone() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        for method in ["device.status", "sys.version", "host.focused_app", nil] as [String?] {
            #expect(sharing.otherReply(method: method, at: 0) == nil)
        }
    }

    @Test func paintsNothingBackWhileAside() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        _ = sharing.front(PadSharing.chatGPT)
        #expect(sharing.otherReply(method: "v.oai.thstatus", at: 0) == nil)
        // A repaint that was waiting when ChatGPT came forward does not block the next one.
        _ = sharing.front(claude)
        #expect(sharing.otherReply(method: "v.oai.thstatus", at: 1) == 0)
        _ = sharing.front(PadSharing.chatGPT)
        _ = sharing.front(claude)
        #expect(sharing.otherReply(method: "v.oai.thstatus", at: 3) == 0)
    }

    @Test func theConfigStepsAsideForChatGPTUnlessToldOtherwise() throws {
        #expect(Config.builtIn.stepAsideFor == [PadSharing.chatGPT])
        #expect(try Config.parse(Config.defaultFileText).stepAsideFor == [PadSharing.chatGPT])
        #expect(try Config.parse(#"{"stepAsideFor": []}"#).stepAsideFor.isEmpty)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"stepAsideFor": "com.openai.codex"}"#) }
    }

    @Test func holdsThePadWhileChatGPTRunsBehind() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        let running: Set = [PadSharing.chatGPT, claude]
        _ = sharing.front(claude)
        #expect(sharing.wantsHold(running: running, layer: 1, typedAt: nil, now: 100))
        // In front, ChatGPT gets the pad.
        _ = sharing.front(PadSharing.chatGPT)
        #expect(!sharing.wantsHold(running: running, layer: 1, typedAt: nil, now: 100))
    }

    @Test func neverHoldsWhenNothingNeedsKeepingOut() {
        let sharing = PadSharing(apps: [PadSharing.chatGPT])
        #expect(!sharing.wantsHold(running: [claude], layer: 1, typedAt: nil, now: 100))
        let none = PadSharing(apps: [])
        #expect(!none.wantsHold(running: [PadSharing.chatGPT], layer: 1, typedAt: nil, now: 100))
    }

    @Test func neverHoldsOffTheFirstLayer() {
        // Off it the pad types as a keyboard, and a held keyboard types nothing.
        let sharing = PadSharing(apps: [PadSharing.chatGPT])
        #expect(!sharing.wantsHold(running: [PadSharing.chatGPT], layer: 2, typedAt: nil, now: 100))
        #expect(!sharing.wantsHold(running: [PadSharing.chatGPT], layer: nil, typedAt: nil, now: 100))
    }

    @Test func staysSharedForAWhileAfterThePadTypes() {
        let sharing = PadSharing(apps: [PadSharing.chatGPT])
        let quiet = PadSharing.keyboardQuiet
        #expect(!sharing.wantsHold(running: [PadSharing.chatGPT], layer: 1, typedAt: 100, now: 100 + quiet - 1))
        #expect(sharing.wantsHold(running: [PadSharing.chatGPT], layer: 1, typedAt: 100, now: 100 + quiet))
    }

    /// `layers` says 2 passes the pad to ChatGPT, which is open, and the pad starts on layer 1.
    private func withALayer(apps: [String] = [PadSharing.chatGPT]) -> PadSharing {
        var sharing = PadSharing(apps: apps)
        sharing.layers = [2: PadSharing.chatGPT]
        _ = sharing.front(claude)
        _ = sharing.layer(1, running: open)
        return sharing
    }

    private var open: Set<String> { [PadSharing.chatGPT, claude] }

    @Test func aVisitToALayerPassesThePadToItsAppAndTheNextVisitTakesItBack() {
        var sharing = withALayer()
        var read = sharing.layer(2, running: open)
        #expect(read.pass == .handed(PadSharing.chatGPT, layer: 2))
        #expect(read.change == .aside(PadSharing.chatGPT))
        #expect(sharing.reason == .visit(2))
        // Back on layer 1 the app still has the pad, whatever is in front.
        read = sharing.layer(1, running: open)
        #expect(read.pass == nil && read.change == nil)
        #expect(sharing.front("com.apple.Terminal") == nil)
        #expect(sharing.asideFor == PadSharing.chatGPT)
        #expect(!sharing.wantsHold(running: open, layer: 1, typedAt: nil, now: 100))

        read = sharing.layer(2, running: open)
        #expect(read.pass == .tookBack(PadSharing.chatGPT, layer: 2))
        #expect(read.change == .back)
        #expect(sharing.asideFor == nil && sharing.handed == nil)
        read = sharing.layer(1, running: open)
        #expect(read.pass == nil && read.change == nil)
        #expect(sharing.wantsHold(running: open, layer: 1, typedAt: nil, now: 100))
    }

    @Test func stayingOnTheLayerIsOneVisit() {
        var sharing = withALayer()
        _ = sharing.layer(2, running: open)
        for _ in 0 ..< 3 {
            let read = sharing.layer(2, running: open)
            #expect(read.pass == nil && read.change == nil)
        }
        #expect(sharing.asideFor == PadSharing.chatGPT)
    }

    /// Nobody tapped: the pad was there when the bridge started, or came back from sleep.
    @Test func thePadsFirstReadingIsNoVisit() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        sharing.layers = [2: PadSharing.chatGPT]
        var read = sharing.layer(2, running: open)
        #expect(read.pass == nil && read.change == nil)
        #expect(sharing.layer(1, running: open).pass == nil)
        // The pad goes away and comes back on layer 2.
        _ = sharing.layer(nil, running: [])
        read = sharing.layer(2, running: open)
        #expect(read.pass == nil && read.change == nil)
    }

    @Test func aPadThatGoesAwayLeavesThePadWithTheAppThatHasIt() {
        var sharing = withALayer()
        _ = sharing.layer(2, running: open)
        let gone = sharing.layer(nil, running: [])
        #expect(gone.pass == nil && gone.change == nil)
        #expect(sharing.layer(1, running: open).change == nil)
        #expect(sharing.asideFor == PadSharing.chatGPT)
    }

    @Test func aVisitForAnAppThatIsNotOpenLeavesThePadWithTheBridge() {
        var sharing = withALayer()
        let read = sharing.layer(2, running: [claude])
        #expect(read.pass == .notOpen(PadSharing.chatGPT, layer: 2))
        #expect(read.change == nil)
        #expect(sharing.asideFor == nil)
        // It was not a first visit either: the next one, with the app open, hands the pad over.
        _ = sharing.layer(1, running: open)
        #expect(sharing.layer(2, running: open).pass == .handed(PadSharing.chatGPT, layer: 2))
    }

    @Test func whenTheAppThatHasThePadQuitsTheBridgeHasItBack() {
        var sharing = withALayer()
        _ = sharing.layer(2, running: open)
        var read = sharing.running(open)
        #expect(read.pass == nil && read.change == nil)
        read = sharing.running([claude])
        #expect(read.pass == .quit(PadSharing.chatGPT))
        #expect(read.change == .back)
        #expect(sharing.asideFor == nil)
        // Said once.
        #expect(sharing.running([claude]).pass == nil)
    }

    @Test func aLayerTakenOutOfTheSettingsTakesThePadBack() {
        var sharing = withALayer()
        _ = sharing.layer(2, running: open)
        sharing.layers = [:]
        #expect(sharing.settle() == .back)
        #expect(sharing.handed == nil)
    }

    @Test func aLayersAppNoLongerGetsThePadByBeingInFront() {
        var sharing = withALayer()
        #expect(sharing.front(PadSharing.chatGPT) == nil)
        #expect(sharing.asideFor == nil)
        // Until a visit the bridge keeps the pad from it, also while it is in front.
        #expect(sharing.wantsHold(running: open, layer: 1, typedAt: nil, now: 100))
        #expect(!sharing.wantsHold(running: open, layer: 2, typedAt: nil, now: 100))
    }

    @Test func aLayerWorksWithoutStepAsideFor() {
        var sharing = withALayer(apps: [])
        #expect(sharing.wantsHold(running: open, layer: 1, typedAt: nil, now: 100))
        #expect(sharing.layer(2, running: open).change == .aside(PadSharing.chatGPT))
    }

    /// Off the first layer nothing is held. This says whether it will be after the tap back.
    @Test func knowsWhetherThePadIsHeldOnceItIsBackOnItsFirstLayer() {
        var sharing = withALayer()
        #expect(sharing.holdsOnFirstLayer(running: open))
        #expect(!sharing.holdsOnFirstLayer(running: [claude]))
        _ = sharing.layer(2, running: open)
        #expect(!sharing.holdsOnFirstLayer(running: open))
    }

    // MARK: Keys on the layers

    /// The pad has its keys on layer 2 as well (`layerKeys`), ChatGPT is open, and the pad
    /// starts on layer 1.
    private func withKeysOnTheLayer(_ layers: [Int: String] = [2: PadSharing.chatGPT]) -> PadSharing {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        sharing.layers = layers
        sharing.layerKeys = true
        _ = sharing.front(claude)
        _ = sharing.layer(1, running: open)
        return sharing
    }

    @Test func withKeysOnTheLayerOneTapGivesItsAppThePadAndOneTapTakesItBack() {
        var sharing = withKeysOnTheLayer()
        #expect(sharing.wantsHold(running: open, layer: 1, typedAt: nil, now: 100))
        var read = sharing.layer(2, running: open)
        #expect(read.pass == .handed(PadSharing.chatGPT, layer: 2))
        #expect(read.change == .aside(PadSharing.chatGPT))
        #expect(sharing.reason == .layer(2))
        #expect(!sharing.wantsHold(running: open, layer: 2, typedAt: nil, now: 100))
        // Whatever is in front, the layer decides.
        #expect(sharing.front("com.apple.Terminal") == nil)
        #expect(sharing.asideFor == PadSharing.chatGPT)

        read = sharing.layer(1, running: open)
        #expect(read.pass == .tookBack(PadSharing.chatGPT, layer: 2))
        #expect(read.change == .back)
        #expect(sharing.asideFor == nil && sharing.handed == nil)
        #expect(sharing.wantsHold(running: open, layer: 1, typedAt: nil, now: 100))
    }

    @Test func withKeysOnTheLayerStayingThereIsSaidOnce() {
        var sharing = withKeysOnTheLayer()
        _ = sharing.layer(2, running: open)
        for _ in 0 ..< 3 {
            let read = sharing.layer(2, running: open)
            #expect(read.pass == nil && read.change == nil)
            let apps = sharing.running(open)
            #expect(apps.pass == nil && apps.change == nil)
        }
        #expect(sharing.asideFor == PadSharing.chatGPT)
    }

    /// No tap is needed: the layer the pad is on says who has it, also when the bridge starts.
    @Test func withKeysOnTheLayerAPadThatStartsThereIsItsApps() {
        var sharing = PadSharing(apps: [PadSharing.chatGPT])
        sharing.layers = [2: PadSharing.chatGPT]
        sharing.layerKeys = true
        let read = sharing.layer(2, running: open)
        #expect(read.pass == .handed(PadSharing.chatGPT, layer: 2))
        #expect(read.change == .aside(PadSharing.chatGPT))
    }

    @Test func withKeysOnTheLayerAnAppThatIsNotOpenLeavesThePadWithTheBridge() {
        var sharing = withKeysOnTheLayer()
        var read = sharing.layer(2, running: [claude])
        #expect(read.pass == .notOpen(PadSharing.chatGPT, layer: 2))
        #expect(read.change == nil)
        #expect(sharing.asideFor == nil)
        // Said once, and not again when the apps are counted.
        #expect(sharing.layer(2, running: [claude]).pass == nil)
        #expect(sharing.running([claude]).pass == nil)
        // The app opens while the pad is on its layer: it gets the pad.
        read = sharing.running(open)
        #expect(read.pass == .handed(PadSharing.chatGPT, layer: 2))
        #expect(read.change == .aside(PadSharing.chatGPT))
    }

    @Test func withKeysOnTheLayerAnAppThatQuitsGivesThePadBack() {
        var sharing = withKeysOnTheLayer()
        _ = sharing.layer(2, running: open)
        let read = sharing.running([claude])
        #expect(read.pass == .quit(PadSharing.chatGPT))
        #expect(read.change == .back)
        // The pad is still on that layer, and the bridge acts on its keys there.
        #expect(sharing.layer(2, running: [claude]).pass == nil)
        #expect(sharing.asideFor == nil)
    }

    @Test func withKeysOnTheLayerAPadThatGoesAwayKeepsWhoHasIt() {
        var sharing = withKeysOnTheLayer()
        _ = sharing.layer(2, running: open)
        let gone = sharing.layer(nil, running: [])
        #expect(gone.pass == nil && gone.change == nil)
        #expect(sharing.running(open).pass == nil)
        #expect(sharing.asideFor == PadSharing.chatGPT)
        // It comes back on layer 1: the bridge has it.
        #expect(sharing.layer(1, running: open).pass == .tookBack(PadSharing.chatGPT, layer: 2))
    }

    @Test func withKeysOnTheLayersEachLayerGivesItsOwnApp() {
        let other = "com.example.other"
        var sharing = withKeysOnTheLayer([2: other, 3: PadSharing.chatGPT])
        let everything: Set<String> = [other, PadSharing.chatGPT, claude]
        var read = sharing.layer(2, running: everything)
        #expect(read.pass == .handed(other, layer: 2) && read.change == .aside(other))
        read = sharing.layer(3, running: everything)
        #expect(read.pass == .handed(PadSharing.chatGPT, layer: 3) && read.change == .aside(PadSharing.chatGPT))
        read = sharing.layer(1, running: everything)
        #expect(read.pass == .tookBack(PadSharing.chatGPT, layer: 3) && read.change == .back)
    }

    /// The bridge has the pad on a layer whose app is not open. Another app that is open must
    /// not hear those keys. A layer without an app may type as a keyboard, and stays shared.
    @Test func withKeysOnTheLayersTheBridgeHoldsThePadWhereItActs() {
        let other = "com.example.other"
        var sharing = withKeysOnTheLayer([2: other, 3: PadSharing.chatGPT])
        #expect(sharing.layer(2, running: open).pass == .notOpen(other, layer: 2))
        #expect(sharing.wantsHold(running: open, layer: 2, typedAt: nil, now: 100))
        #expect(!sharing.wantsHold(running: open, layer: 4, typedAt: nil, now: 100))
        // Without keys on the layers nothing is held off the first one.
        sharing.layerKeys = false
        #expect(!sharing.wantsHold(running: open, layer: 2, typedAt: nil, now: 100))
    }

    @Test func withKeysOnTheLayerItIsReadOftenWhileItsAppIsOpen() {
        var sharing = withKeysOnTheLayer()
        #expect(sharing.watchesLayer(running: open))
        #expect(!sharing.watchesLayer(running: [claude]))
        sharing.layerKeys = false
        #expect(!sharing.watchesLayer(running: open))
    }

    @Test func turningTheKeysOnTheLayersOffLeavesAVisitsRule() {
        var sharing = withKeysOnTheLayer()
        _ = sharing.layer(2, running: open)
        sharing.layerKeys = false
        // The app keeps the pad until the next visit takes it back.
        #expect(sharing.layer(1, running: open).pass == nil)
        #expect(sharing.asideFor == PadSharing.chatGPT)
        #expect(sharing.layer(2, running: open).pass == .tookBack(PadSharing.chatGPT, layer: 2))
    }

    @Test func layerKeysIsReadFromTheConfig() throws {
        #expect(try !Config.parse(Config.defaultFileText).layerKeys)
        #expect(try Config.parse(#"{"layerKeys": true}"#).layerKeys)
        #expect(throws: ConfigError.self) { try Config.parse(#"{"layerKeys": "yes"}"#) }
    }

    @Test func layersAreReadFromTheConfig() throws {
        #expect(try Config.parse(Config.defaultFileText).layers.isEmpty)
        #expect(try Config.parse(#"{"layers": {"2": "com.openai.codex"}}"#).layers == [2: PadSharing.chatGPT])
        // Layer 1 is the bridge's.
        #expect(throws: ConfigError.self) { try Config.parse(#"{"layers": {"1": "com.openai.codex"}}"#) }
        #expect(throws: ConfigError.self) { try Config.parse(#"{"layers": {"2": 3}}"#) }
        #expect(throws: ConfigError.self) { try Config.parse(#"{"layers": ["com.openai.codex"]}"#) }
    }
}
