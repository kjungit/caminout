// swift-tools-version:6.0
import PackageDescription

// 설정·프리셋 모델, 자르기 계산, 얼굴 데이터 모델.
// UI·미디어 프레임워크에 의존하지 않는다 (기술 설계서 4장).
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
