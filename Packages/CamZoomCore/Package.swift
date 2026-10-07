// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CamZoomCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CamZoomCore", targets: ["CamZoomCore"])
    ],
    targets: [
        .target(name: "CamZoomCore"),
        .testTarget(name: "CamZoomCoreTests", dependencies: ["CamZoomCore"])
    ]
)
