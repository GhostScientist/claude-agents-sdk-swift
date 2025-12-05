// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AgentSDK",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        // Core SDK - platform agnostic
        .library(
            name: "AgentSDK",
            targets: ["AgentSDK"]
        ),
        // Claude provider
        .library(
            name: "ClaudeProvider",
            targets: ["ClaudeProvider"]
        ),
        // Apple platform extensions (SwiftUI, App Intents)
        .library(
            name: "AgentSDKApple",
            targets: ["AgentSDKApple"]
        ),
    ],
    dependencies: [
        // Swift Syntax for macro implementation
        .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0"),
    ],
    targets: [
        // MARK: - Core SDK
        .target(
            name: "AgentSDK",
            dependencies: ["AgentSDKMacros"],
            path: "Sources/AgentSDK"
        ),

        // MARK: - Macros
        .macro(
            name: "AgentSDKMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/AgentSDKMacros"
        ),

        // MARK: - Providers
        .target(
            name: "ClaudeProvider",
            dependencies: ["AgentSDK"],
            path: "Sources/ClaudeProvider"
        ),

        // MARK: - Apple Platform Extensions
        .target(
            name: "AgentSDKApple",
            dependencies: ["AgentSDK"],
            path: "Sources/AgentSDKApple"
        ),

        // MARK: - Tests
        .testTarget(
            name: "AgentSDKTests",
            dependencies: ["AgentSDK"]
        ),
        .testTarget(
            name: "AgentSDKMacrosTests",
            dependencies: [
                "AgentSDKMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: "ClaudeProviderTests",
            dependencies: ["ClaudeProvider"]
        ),
    ]
)
