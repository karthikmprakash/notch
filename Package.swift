// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Notch", targets: ["Notch"])
    ],
    targets: [
        .executableTarget(name: "Notch", path: "Sources/Notch"),
        .testTarget(name: "NotchTests", dependencies: ["Notch"])
    ]
)
