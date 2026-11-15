// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidyFixer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TidyFixer", path: "Sources/TidyFixer"),
        .testTarget(
            name: "TidyFixerTests",
            dependencies: ["TidyFixer"],
            path: "Tests/TidyFixerTests"
        ),
    ]
)
