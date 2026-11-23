// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "micro-bridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "micro", targets: ["micro"]),
        .executable(name: "micro-helper", targets: ["micro-helper"]),
    ],
    targets: [
        // The pad's wire format, its five allowed methods and finding it. No AppKit: the root
        // helper links only this.
        .target(name: "PadWire", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        // The optional helper that runs as root and holds the pad for MicroBridge alone.
        .executableTarget(name: "micro-helper", dependencies: ["PadWire"],
                          linkerSettings: [.linkedFramework("Security")]),
        .target(
            name: "MicroKit",
            dependencies: ["PadWire"],
            linkerSettings: [
                .linkedFramework("IOKit"), .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"), .linkedFramework("AppKit"),
            ]
        ),
        // The window: SwiftUI on top of MicroKit. It talks to the running daemon over its socket.
        .target(name: "MicroUI", dependencies: ["MicroKit"]),
        .executableTarget(name: "micro", dependencies: ["MicroKit", "MicroUI"]),
        .testTarget(name: "PadWireTests", dependencies: ["PadWire"]),
        .testTarget(name: "MicroKitTests", dependencies: ["MicroKit"]),
        .testTarget(name: "MicroUITests", dependencies: ["MicroKit", "MicroUI"]),
    ]
)
