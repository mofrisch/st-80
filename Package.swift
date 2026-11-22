// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Smalltalk80",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SmalltalkCore", targets: ["SmalltalkCore"]),
        .executable(name: "Smalltalk80", targets: ["Smalltalk80"]),
    ],
    targets: [
        .target(name: "SmalltalkCore"),
        .executableTarget(name: "Smalltalk80", dependencies: ["SmalltalkCore"]),
        .testTarget(name: "SmalltalkCoreTests", dependencies: ["SmalltalkCore"]),
    ]
)
