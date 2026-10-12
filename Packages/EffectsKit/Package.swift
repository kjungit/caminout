// swift-tools-version:6.0
import PackageDescription

// 레이어 합성 엔진: 레이어 프로토콜, 합성기, 기본 효과 (기술 설계서 4·7장).
let package = Package(
    name: "EffectsKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "EffectsKit", targets: ["EffectsKit"])
    ],
    dependencies: [
        .package(path: "../CamZoomCore")
    ],
    targets: [
        .target(name: "EffectsKit", dependencies: ["CamZoomCore"]),
        .testTarget(name: "EffectsKitTests", dependencies: ["EffectsKit"])
    ]
)
