// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "turnring",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "turnring", path: "Sources/turnring"),
        .testTarget(name: "turnringTests", dependencies: ["turnring"], path: "Tests/turnringTests"),
    ]
)
