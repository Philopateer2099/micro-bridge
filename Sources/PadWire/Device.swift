import CoreFoundation
import Foundation
import IOKit
import IOKit.hid

public enum PadModel {
    public static let vendorID = 0x303A // Espressif's VID: always check the product ID too
    public static let vendorUsagePage = 0xFF00
    public static let products: [Int: String] = [
        0x8360: "Codex Micro",
        0x8297: "Creator Micro 2",
        0x8298: "Creator Micro 2",
    ]
}

public struct UsagePair: Sendable, Equatable, Codable {
    public let page: Int
    public let usage: Int

    public init(page: Int, usage: Int) {
        self.page = page
        self.usage = usage
    }
}

public struct PadInfo: Sendable, Codable, Equatable {
    public let productID: Int
    public let model: String
    public let transport: String
    public let product: String?
    public let usagePairs: [UsagePair]
    public let maxInputReport: Int
    public let maxOutputReport: Int

    public init(productID: Int, model: String, transport: String, product: String?, usagePairs: [UsagePair],
                maxInputReport: Int, maxOutputReport: Int) {
        self.productID = productID
        self.model = model
        self.transport = transport
        self.product = product
        self.usagePairs = usagePairs
        self.maxInputReport = maxInputReport
        self.maxOutputReport = maxOutputReport
    }

    /// True when the device carries the vendor RPC interface.
    public var hasVendorInterface: Bool {
        usagePairs.contains { $0.page == PadModel.vendorUsagePage }
    }

    public var isUSB: Bool { transport.uppercased() == "USB" }
}

/// The only RPC methods this project sends. The pad also accepts file-system, bootloader and
/// firmware methods on the same channel; leaving them out of this enum makes them impossible
/// to call. Do not add a method here without reading what it does to the device.
public enum Method: String, CaseIterable, Sendable {
    case version = "sys.version"
    case status = "device.status"
    case threadsLighting = "v.oai.thstatus"
    case lightingConfig = "v.oai.rgbcfg"
    case lightingPreview = "lights.preview"
}

/// Finding attached pads.
public enum PadDevices {
    /// Every attached pad that carries the vendor interface, USB first.
    public static func all() -> [(device: IOHIDDevice, info: PadInfo)] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = PadModel.products.keys.map { pid -> [String: Int] in
            [kIOHIDVendorIDKey: PadModel.vendorID, kIOHIDProductIDKey: pid]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        let list = (set as NSSet).allObjects.map { $0 as! IOHIDDevice }
        return list.compactMap { device -> (device: IOHIDDevice, info: PadInfo)? in
            let info = describe(device)
            return info.hasVendorInterface ? (device, info) : nil
        }.sorted { $0.info.isUSB && !$1.info.isUSB }
    }

    private static func describe(_ device: IOHIDDevice) -> PadInfo {
        func property(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
        let pid = property(kIOHIDProductIDKey) as? Int ?? 0
        var pairs: [UsagePair] = []
        if let raw = property(kIOHIDDeviceUsagePairsKey) as? [[String: Any]] {
            pairs = raw.compactMap { d in
                guard let page = d[kIOHIDDeviceUsagePageKey] as? Int, let usage = d[kIOHIDDeviceUsageKey] as? Int
                else { return nil }
                return UsagePair(page: page, usage: usage)
            }
        }
        if pairs.isEmpty, let page = property(kIOHIDPrimaryUsagePageKey) as? Int {
            pairs = [UsagePair(page: page, usage: property(kIOHIDPrimaryUsageKey) as? Int ?? 0)]
        }
        return PadInfo(
            productID: pid,
            model: PadModel.products[pid] ?? "unknown",
            transport: property(kIOHIDTransportKey) as? String ?? "unknown",
            product: property(kIOHIDProductKey) as? String,
            usagePairs: pairs,
            maxInputReport: property(kIOHIDMaxInputReportSizeKey) as? Int ?? Framing.reportSize,
            maxOutputReport: property(kIOHIDMaxOutputReportSizeKey) as? Int ?? Framing.reportSize
        )
    }
}
