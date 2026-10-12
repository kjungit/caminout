// swift-tools-version:6.0
import PackageDescription

// 가상 카메라 장치 찾기, sink 큐에 프레임 넣기, 사용 중 여부 감지 (기술 설계서 4·6장).
let package = Package(
    name: "CameraBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CameraBridge", targets: ["CameraBridge"])
    ],
    dependencies: [
        .package(path: "../CamZoomShared")
    ],
    targets: [
        .target(name: "CameraBridge", dependencies: ["CamZoomShared"]),
        .testTarget(name: "CameraBridgeTests", dependencies: ["CameraBridge"])
    ]
)
