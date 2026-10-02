// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SundayKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SundayKit", targets: ["SundayKit"]),
    ],
    targets: [
        .target(name: "SundayKit"),
        .testTarget(name: "SundayKitTests", dependencies: ["SundayKit"]),
    ]
)
