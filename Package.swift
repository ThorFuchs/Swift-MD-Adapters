// swift-tools-version: 6.1
// Generated; edit SwiftMD instead. DO NOT EDIT THIS MIRROR.
import PackageDescription
let package = Package(
    name: "SwiftMDAdapters",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "SwiftMDBlocks", targets: ["SwiftMDBlocks"]),
        .library(name: "SwiftMDHighlight", targets: ["SwiftMDHighlight"]),
        .library(name: "SwiftMDKaTeXNode", targets: ["SwiftMDKaTeXNode"]),
        .library(name: "SwiftMDPeleNode", targets: ["SwiftMDPeleNode"]),
        .library(name: "SwiftMDCompiler", targets: ["SwiftMDCompiler"]),
        .library(name: "SwiftMDJavaScriptCore", targets: ["SwiftMDJavaScriptCore"]),
        .library(name: "SwiftMDBundled", targets: ["SwiftMDBundled"]),
        .executable(name: "swift-md", targets: ["SwiftMDCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ThorFuchs/Swift-MD.git", exact: "1.0.0"),
        .package(url: "https://github.com/ThorFuchs/Swift-GFM.git", exact: "1.0.1"),
        .package(url: "https://github.com/ThorFuchs/Swift-Highlight.git", exact: "1.0.1"),
        .package(url: "https://github.com/nicklockwood/LRUCache.git", exact: "1.3.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.3.1"),
    ],
    targets: [
        .target(name: "SwiftMDSoup", dependencies: [.product(name: "LRUCache", package: "LRUCache"), .product(name: "Atomics", package: "swift-atomics")], path: "Adapters/SwiftMDBlocks/Vendor/SwiftSoup", exclude: ["UPSTREAM.json"], sources: ["Sources"], resources: [.copy("LICENSE"), .copy("JSOUP-LICENSE.txt")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SwiftMDBlocks", dependencies: [.product(name: "SwiftMD", package: "Swift-MD"), "SwiftMDSoup"], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDBlocks"),
        .target(name: "SwiftMDHighlight", dependencies: ["SwiftMDBlocks", .product(name: "SwiftHighlight", package: "Swift-Highlight"), .product(name: "SwiftHighlightHTML", package: "Swift-Highlight")], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDHighlight"),
        .target(name: "SwiftMDKaTeXNode", dependencies: ["SwiftMDBlocks"], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDKaTeXNode"),
        .target(name: "SwiftMDPeleNode", dependencies: ["SwiftMDBlocks", "SwiftMDKaTeXNode"], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDPeleNode"),
        .target(name: "SwiftMDCompiler", dependencies: ["SwiftMDBlocks", "SwiftMDHighlight", "SwiftMDKaTeXNode", "SwiftMDPeleNode", .product(name: "SwiftMD", package: "Swift-MD"), .product(name: "SwiftGFM", package: "Swift-GFM")], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDCompiler"),
        .target(name: "SwiftMDJavaScriptCore", dependencies: ["SwiftMDBlocks", "SwiftMDHighlight", .product(name: "SwiftMD", package: "Swift-MD"), .product(name: "SwiftGFM", package: "Swift-GFM")], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDJavaScriptCore"),
        .target(name: "SwiftMDBundled", dependencies: ["SwiftMDBlocks", .target(name: "SwiftMDJavaScriptCore", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS])), .target(name: "SwiftMDCompiler", condition: .when(platforms: [.linux]))], path: "Adapters/SwiftMDBlocks/Sources/SwiftMDBundled", resources: [.copy("RendererAssets")]),
        .executableTarget(name: "SwiftMDCLI", dependencies: ["SwiftMDBlocks", "SwiftMDHighlight", "SwiftMDKaTeXNode", "SwiftMDPeleNode", .product(name: "SwiftMD", package: "Swift-MD"), .product(name: "SwiftGFM", package: "Swift-GFM")], path: "Tools/SwiftMDCLI/Sources/SwiftMDCLI"),
        .testTarget(name: "SwiftMDBlocksTests", dependencies: ["SwiftMDBlocks", "SwiftMDHighlight", "SwiftMDKaTeXNode", "SwiftMDPeleNode", "SwiftMDCompiler", "SwiftMDJavaScriptCore", "SwiftMDSoup", .product(name: "SwiftGFM", package: "Swift-GFM"), .product(name: "SwiftMD", package: "Swift-MD")], path: "Adapters/SwiftMDBlocks/Tests/SwiftMDBlocksTests"),
    ], swiftLanguageModes: [.v6]
)
