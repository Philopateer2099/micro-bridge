import Foundation

/// Who drives the pad when another app, such as ChatGPT, has it open too. Both apps hear every
/// press and both can write the lights, and macOS lets only root shut the other out. So the
/// bridge goes quiet while one of `apps` is in front: no lights, no key actions. While any
/// other app is in front, a light write from another app is painted over with the bridge's own,
/// and with MicroBridge Helper installed the pad is held so that app hears nothing at all.
///
/// A layer can pass the pad to an app instead (`layers`). The pad's own keys for these apps
/// exist only on layer 1, so no layer can be the other app's. A visit to that layer is the
/// signal: it gives the app the pad, and the next visit takes it back. In between the app has
/// the pad on layer 1 whatever is in front, and until then the bridge keeps it, also from
/// that app. A tap on the pad's touch sensor goes to the layer, a second tap comes back.
///
/// A pad whose keys were put on those layers as well (`layerKeys`) needs no second tap: the
/// layer it is on says who has it. On a layer in `layers` that is its app, on every other
/// layer the bridge.
///
/// The bridge can have layers of its own besides the first (`own`): the pad's keys are there
/// too, and the bridge acts on them itself, for the agents of an app that does not drive the
/// pad, such as Orca. No app gets the pad by such a layer.
public struct PadSharing: Sendable {
    /// Bundle ids the bridge leaves the pad to while one of them is in front.
    public var apps: [String]
    /// Layers whose visit passes the pad to another app, by number. That app no longer gets
    /// the pad by being in front.
    public var layers: [Int: String] = [:]
    /// The pad has its own keys on the layers in `layers` too, not only on the first one. Then
    /// being on a layer gives its app the pad, and leaving it gives the pad back.
    public var layerKeys = false
    /// Layers besides the first that the bridge drives itself. The pad has its keys there.
    public var own: Set<Int> = []
    /// The app the bridge is leaving the pad to now, if any.
    public private(set) var asideFor: String?
    /// Why: that app is in front, a visit to that layer gave it the pad, or the pad is on
    /// its layer.
    public private(set) var reason: Reason?
    /// The app a layer gave the pad to, and that layer. It stays when the pad goes away and
    /// comes back: only the layer, the app quitting or the settings change it.
    public private(set) var handed: Handed?
    private var frontApp: String?
    private var padLayer: Int?
    /// With `layerKeys`: the layer the bridge has the pad on, once that was said. An app that
    /// is not open is reported once per stay on its layer, not at every reading.
    private var said: Int?
    private var repaintDue = false
    private var lastRepaint = -Double.infinity

    public struct Handed: Equatable, Sendable {
        public var app: String
        public var layer: Int
    }

    public enum Reason: Equatable, Sendable {
        case front
        case visit(Int)
        /// The pad is on that layer, which has its keys (`layerKeys`).
        case layer(Int)
    }

    /// What a reading of the layer, or of the running apps, did about who has the pad.
    public enum Pass: Equatable, Sendable {
        /// Its layer gave that app the pad.
        case handed(String, layer: Int)
        /// The pad was taken back from the app that layer gave it to: by a second visit, or
        /// with `layerKeys` by leaving the layer.
        case tookBack(String, layer: Int)
        /// The pad is on the layer of an app that is not open: the bridge keeps the pad.
        case notOpen(String, layer: Int)
        /// The app that had the pad quit: the bridge has it back.
        case quit(String)
    }

    /// The ChatGPT app's bundle id.
    public static let chatGPT = "com.openai.codex"
    /// Repaints after other apps' light writes come at most this often.
    public static let repaintGap: TimeInterval = 1
    /// Methods that change the lights.
    static let lightMethods: Set<String> = [
        Method.threadsLighting.rawValue, Method.lightingConfig.rawValue, Method.lightingPreview.rawValue,
    ]

    public enum Change: Equatable, Sendable {
        /// That app has the pad now: leave the pad alone.
        case aside(String)
        /// The bridge has the pad: paint the lights and act on keys again.
        case back
    }

    public init(apps: [String]) {
        self.apps = apps
    }

    /// Notes the app in front now. Nil when nothing changes for the bridge.
    public mutating func front(_ app: String?) -> Change? {
        frontApp = app
        return settle()
    }

    /// Notes the pad's layer now, nil when the pad is gone. Coming to a layer in `layers` from
    /// another one is a visit. The first reading of a pad is not: nobody tapped. With
    /// `layerKeys` there are no visits, and every reading says who has the pad.
    public mutating func layer(_ layer: Int?, running: Set<String>) -> (pass: Pass?, change: Change?) {
        let before = padLayer
        padLayer = layer
        if layerKeys { return stay(running: running) }
        guard let layer, let before, layer != before, let app = layers[layer] else { return (nil, settle()) }
        let pass: Pass
        if handed?.app == app {
            handed = nil
            pass = .tookBack(app, layer: layer)
        } else if running.contains(app) {
            handed = Handed(app: app, layer: layer)
            pass = .handed(app, layer: layer)
        } else {
            pass = .notOpen(app, layer: layer)
        }
        return (pass, settle())
    }

    /// Notes the apps that run now. An app that quit cannot drive the pad: the bridge has it back.
    /// With `layerKeys`, an app that opens while the pad is on its layer gets the pad.
    public mutating func running(_ running: Set<String>) -> (pass: Pass?, change: Change?) {
        if layerKeys, padLayer != nil { return stay(running: running) }
        guard let app = handed?.app, !running.contains(app) else { return (nil, nil) }
        handed = nil
        return (.quit(app), settle())
    }

    /// With `layerKeys`: the layer the pad is on says who has it. Its app when that is open,
    /// the bridge on every other layer and while that app is closed.
    private mutating func stay(running: Set<String>) -> (pass: Pass?, change: Change?) {
        // A pad that is gone changes nothing. It comes back on some layer, and that one says.
        guard let layer = padLayer else { return (nil, nil) }
        if said != layer { said = nil }
        var pass: Pass?
        if let app = layers[layer], running.contains(app) {
            let its = Handed(app: app, layer: layer)
            if handed != its {
                handed = its
                pass = .handed(app, layer: layer)
            }
            said = nil
        } else {
            if let had = handed {
                handed = nil
                // Still on its layer, so the app went away, not the pad.
                pass = had.layer == layer ? .quit(had.app) : .tookBack(had.app, layer: had.layer)
            } else if let app = layers[layer], said == nil {
                pass = .notOpen(app, layer: layer)
            }
            said = layer
        }
        return (pass, settle())
    }

    /// Whether the pad's own keys reach its apps on that layer: the first one, the bridge's
    /// other layers (`own`), and with `layerKeys` every layer in `layers`.
    public func hasKeys(on layer: Int) -> Bool {
        layer == LayerWatch.ours || own.contains(layer) || (layerKeys && layers[layer] != nil)
    }

    /// Whether one tap can change whose keys the pad's are now, so the layer is worth reading
    /// often: the bridge has more than one layer of its own, or the layers have the pad's
    /// keys and one of their apps is open.
    public func watchesLayer(running: Set<String>) -> Bool {
        !own.isEmpty || (layerKeys && layers.values.contains(where: running.contains))
    }

    /// Settings changed: works out who has the pad again.
    public mutating func settle() -> Change? {
        // A layer taken out of the settings no longer gives anyone the pad.
        if let given = handed, layers[given.layer] != given.app { handed = nil }
        let owners = Set(layers.values)
        let now: String?
        if let handed {
            now = handed.app
            reason = layerKeys ? .layer(handed.layer) : .visit(handed.layer)
        } else if let frontApp, apps.contains(frontApp), !owners.contains(frontApp) {
            now = frontApp
            reason = .front
        } else {
            now = nil
            reason = nil
        }
        guard now != asideFor else { return nil }
        asideFor = now
        repaintDue = false
        return now.map(Change.aside) ?? .back
    }

    /// Whether the pad would be held on its first layer now. Off that layer it is the time to
    /// look often: the tap back comes soon, and the pad must be held again by the next press.
    public func holdsOnFirstLayer(running: Set<String>) -> Bool {
        wantsHold(running: running, layer: LayerWatch.ours, typedAt: nil, now: 0)
    }

    /// Another app's request got its answer. Returns how many seconds to wait before painting
    /// the bridge's lights back, or nil to leave them: it was not a light write, the bridge is
    /// aside, or a repaint is already waiting.
    public mutating func otherReply(method: String?, at now: TimeInterval) -> TimeInterval? {
        guard asideFor == nil, !repaintDue, let method, Self.lightMethods.contains(method) else { return nil }
        repaintDue = true
        return max(0, lastRepaint + Self.repaintGap - now)
    }

    /// The waiting repaint runs now.
    public mutating func repainting(at now: TimeInterval) {
        repaintDue = false
        lastRepaint = now
    }

    /// After the pad sends a report as a keyboard or mouse would, how long it stays shared.
    public static let keyboardQuiet: TimeInterval = 10

    /// Whether to keep the pad from other apps now, through MicroBridge Helper: one of `apps`
    /// is running but none is in front, and the pad is on a layer that has its keys. On any
    /// other layer the pad types as a keyboard, and a held keyboard types nothing, so the pad
    /// stays shared for `keyboardQuiet` seconds after its last keyboard or mouse report
    /// (`typedAt`).
    public func wantsHold(running: Set<String>, layer: Int?, typedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard asideFor == nil, let layer, hasKeys(on: layer),
              (apps + layers.values).contains(where: running.contains) else { return false }
        if let typedAt, now - typedAt < Self.keyboardQuiet { return false }
        return true
    }
}
