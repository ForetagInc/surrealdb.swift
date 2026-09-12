// swift-tools-version: 6.1

import CompilerPluginSupport
import Foundation
import PackageDescription

// The embedded (mem://) engine links a ~150 MB Rust static library built from
// surrealdb.c, so it is opt-in: without SURREALDB_EMBEDDED the C targets are not
// in the graph at all and the package resolves exactly as it did before.
//
//   ./scripts/build-embedded.sh
//   export PKG_CONFIG_PATH="$PWD/.build/embedded/out/pkgconfig"
//   SURREALDB_EMBEDDED=1 swift build
//
// SwiftPM caches compiled manifests without the environment in the key, so pass
// --manifest-cache none when toggling this.
let embeddedEnabled = ProcessInfo.processInfo.environment["SURREALDB_EMBEDDED"] == "1"

let embeddedTargets: [Target] = embeddedEnabled
    ? [
        .systemLibrary(name: "CSurrealDB", path: "Sources/CSurrealDB", pkgConfig: "surrealdb_c"),
    ]
    : []

let embeddedDependencies: [Target.Dependency] = embeddedEnabled ? ["CSurrealDB"] : []
let embeddedSettings: [SwiftSetting] = embeddedEnabled ? [.define("SURREALDB_EMBEDDED")] : []

let package = Package(
    name: "SurrealDB",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SurrealDB", targets: ["SurrealDB"]),
        .library(name: "AgentMemory", targets: ["AgentMemory"])
    ],
    dependencies: [
        .package(url: "https://github.com/outfoxx/PotentCodables.git", from: "3.5.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.1")
    ],
    targets: [
        .target(
            name: "SurrealDBMacros"
        ),
        .macro(
            name: "SurrealDBMacroPlugin",
            dependencies: [
                "SurrealDBMacros",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SurrealDB",
            dependencies: [
                "SurrealDBMacros",
                "SurrealDBMacroPlugin",
                .product(name: "PotentCodables", package: "PotentCodables")
            ] + embeddedDependencies,
            swiftSettings: embeddedSettings
        ),
        .testTarget(
            name: "SurrealDBTests",
            dependencies: [
                "SurrealDB",
                "SurrealDBMacroPlugin",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ],
            swiftSettings: embeddedSettings
        ),
        .target(
            name: "AgentMemory"
        ),
        .testTarget(
            name: "AgentMemoryTests",
            dependencies: ["AgentMemory"]
        )
    ] + embeddedTargets
)
