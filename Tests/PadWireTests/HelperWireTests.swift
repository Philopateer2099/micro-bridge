import Foundation
@testable import PadWire
import Testing

struct HelperWireTests {
    let info = PadInfo(productID: 0x8360, model: "Codex Micro", transport: "USB", product: "Codex Micro",
                       usagePairs: [UsagePair(page: 1, usage: 6), UsagePair(page: 0xFF00, usage: 1)],
                       maxInputReport: 64, maxOutputReport: 64)

    @Test func everyFrameReadsBackAsSent() {
        let frames: [HelperWire.Frame] = [
            .send(#"{"method":"sys.version","params":null,"id":7}"#), .hold(true), .hold(false), .info(info),
            .sent(0), .sent(Int32(bitPattern: 0xE000_02C5)), .holding(true, 0), .report(Array(repeating: 6, count: 64)),
            .gone, .refused("not MicroBridge"),
        ]
        var reader = HelperWire.FrameReader()
        #expect(reader.feed(frames.flatMap(\.encoded)) == frames)
        #expect(!reader.broken)
    }

    @Test func aFrameSplitAcrossReadsWaitsForTheRest() {
        let bytes = HelperWire.Frame.report(Array(0 ..< 64)).encoded
        var reader = HelperWire.FrameReader()
        #expect(reader.feed(Array(bytes[0 ..< 3])).isEmpty)
        #expect(reader.feed(Array(bytes[3 ..< 40])).isEmpty)
        #expect(reader.feed(Array(bytes[40...])) == [.report(Array(0 ..< 64))])
    }

    @Test func anUnknownTypeOrAHugeLengthBreaksTheConnection() {
        var unknown = HelperWire.FrameReader()
        #expect(unknown.feed([0x42, 0, 0, 0, 0]).isEmpty)
        #expect(unknown.broken)
        var huge = HelperWire.FrameReader()
        #expect(huge.feed([0x84, 0x7F, 0xFF, 0xFF, 0xFF]).isEmpty)
        #expect(huge.broken)
        // Nothing after a broken frame is read.
        #expect(huge.feed(HelperWire.Frame.gone.encoded).isEmpty)
    }

    @Test func theFiveMethodsPassAsTheyAreSent() throws {
        for method in Method.allCases {
            let sent = #"{"method":"\#(method.rawValue)","params":[{"slot":0,"color":3165950}],"id":42}"#
            let checked = try #require(HelperWire.checkedRequest(sent))
            let object = try #require(try JSONSerialization.jsonObject(with: Data(checked.utf8)) as? [String: Any])
            #expect(object["method"] as? String == method.rawValue)
            #expect(object["id"] as? Int == 42)
            #expect(checked.hasPrefix(#"{"method":"\#(method.rawValue)","params":"#))
        }
    }

    @Test func everythingElseIsRefused() {
        let refused = [
            #"{"method":"fs.format","params":null,"id":1}"#,
            #"{"method":"sys.bootloader","id":1}"#,
            #"{"method":"host.focused_app","params":{"app":"x"},"id":1}"#,
            #"{"m":"fs.write","id":1}"#,
            #"{"method":"sys.version","id":1,"extra":true}"#,
            #"{"method":"sys.version","id":1.5}"#,
            #"{"method":"sys.version","id":true}"#,
            #"{"method":"sys.version","id":"1"}"#,
            #"{"method":"sys.version"}"#,
            #"[{"method":"sys.version","id":1}]"#,
            "not json",
            #"{"method":"sys.version","params":""# + String(repeating: "x", count: 5000) + #"","id":1}"#,
        ]
        for text in refused { #expect(HelperWire.checkedRequest(text) == nil, "\(text.prefix(60))") }
    }

    @Test func aSecondMethodKeyCannotReachThePad() throws {
        // JSON readers differ on repeated keys. The helper rebuilds the text from the one it checked.
        let text = #"{"method":"sys.version","method":"fs.format","id":3}"#
        if let checked = HelperWire.checkedRequest(text) {
            #expect(!checked.contains("fs."))
            #expect(checked.components(separatedBy: "\"method\"").count == 2)
        }
    }

    @Test func nonASCIIIsEscapedAsTheVendorAppDoes() throws {
        let checked = try #require(HelperWire.checkedRequest(#"{"method":"lights.preview","params":{"name":"caf\#u{e9}"},"id":1}"#))
        let ascii = checked.unicodeScalars.allSatisfy(\.isASCII)
        #expect(ascii)
        #expect(checked.contains(#"\u00e9"#))
    }
}
