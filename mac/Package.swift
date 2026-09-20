// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lyra",
    platforms: [.macOS("14.2")],
    products: [.library(name: "LyraCore", targets: ["LyraCore"]), .executable(name: "Lyra", targets: ["Lyra"])],
    targets: [
        .target(name: "LyraCore"),
        .executableTarget(name: "Lyra", dependencies: ["LyraCore"]),
        .testTarget(name: "LyraCoreTests", dependencies: ["LyraCore"])
    ]
)
