// swift-tools-version:5.9
import PackageDescription

// StackGameCore deliberately declares no platform-specific dependencies.
// It must stay buildable anywhere Swift runs so the gameplay rules can be
// tested without a simulator, a GPU, or a Mac.
let package = Package(
    name: "StackGameCore",
    products: [
        .library(name: "StackGameCore", targets: ["StackGameCore"])
    ],
    targets: [
        .target(name: "StackGameCore"),
        .testTarget(name: "StackGameCoreTests", dependencies: ["StackGameCore"])
    ]
)
