// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskScope",
    defaultLocalization: "ru",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskScope", targets: ["DiskScope"]),
        .executable(name: "diskscope-cli", targets: ["DiskScopeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "DiskScopeKit",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Photos")]
        ),
        .executableTarget(
            name: "DiskScope",
            dependencies: ["DiskScopeKit", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .executableTarget(name: "DiskScopeCLI", dependencies: ["DiskScopeKit"]),
        .executableTarget(name: "DiskScopeSnapshots", dependencies: ["DiskScopeKit"]),
        .testTarget(name: "DiskScopeKitTests", dependencies: ["DiskScopeKit"]),
    ]
)
