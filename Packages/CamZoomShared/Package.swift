// swift-tools-version:6.0
import PackageDescription

// 앱과 카메라 익스텐션이 함께 쓰는 값: 장치·스트림 ID, 출력 형식, 사용자 정의 속성, 안내 화면.
// 익스텐션은 이 패키지 하나만 의존한다 (기술 설계서 4장).
let package = Package(
    name: "CamZoomShared",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CamZoomShared", targets: ["CamZoomShared"])
    ],
    targets: [
        .target(name: "CamZoomShared"),
        .testTarget(name: "CamZoomSharedTests", dependencies: ["CamZoomShared"])
    ]
)
