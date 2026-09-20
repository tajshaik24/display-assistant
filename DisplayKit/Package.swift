// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DisplayKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DisplayKit", targets: ["DisplayKit"]),
        .executable(name: "displayctl", targets: ["displayctl"]),
    ],
    targets: [
        // Declarations for the private IOAVService I2C functions exported by IOKit.
        .target(
            name: "CIOAVService",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "DisplayKit",
            dependencies: ["CIOAVService"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DisplayKitTests",
            dependencies: ["DisplayKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "displayctl",
            dependencies: ["DisplayKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
