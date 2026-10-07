// swift-tools-version:6.0
import PackageDescription

// 카메라 캡처와 검증용 가짜 입력 (기술 설계서 4·11장, 검증 계획 4장).
let package = Package(
    name: "CaptureKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CaptureKit", targets: ["CaptureKit"])
    ],
    dependencies: [
        .package(path: "../CamZoomCore")
    ],
    targets: [
        .target(name: "CaptureKit", dependencies: ["CamZoomCore"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"])
    ]
)
