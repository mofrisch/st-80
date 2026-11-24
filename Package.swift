// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Smalltalk80",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SmalltalkCore", targets: ["SmalltalkCore"]),
        .executable(name: "Smalltalk80", targets: ["Smalltalk80"]),
        .executable(name: "st80-bootstrap", targets: ["SmalltalkBootstrap"]),
    ],
    targets: [
        .target(name: "SmalltalkCore", resources: [.copy("Library")]),
        .executableTarget(
            name: "Smalltalk80",
            dependencies: ["SmalltalkCore"],
            exclude: ["Assets.xcassets"]
        ),
        .executableTarget(name: "SmalltalkBootstrap", dependencies: ["SmalltalkCore"]),
        .testTarget(name: "SmalltalkCoreTests", dependencies: ["SmalltalkCore"], resources: [.copy("SmalltalkTests")]),
    ]
)
