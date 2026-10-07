# CamZoom (가칭)

맥북 카메라를 조절하고, 꾸미고, 캐릭터로 바꿔서 Zoom·Discord·ZEP 등
모든 화상 서비스에 그대로 내보내는 맥 전용 무료 가상 카메라 앱.

모든 기획·설계 문서는 [`docs/`](docs/README.md)에 있습니다. 처음이라면
[`docs/00-overview.md`](docs/00-overview.md)(종합 문서)부터 읽어 주세요.

> 이름의 "Zoom"은 실제 화상회의 서비스와 혼동될 수 있어 정식 이름이
> 아닙니다. 최종 이름은 아직 정하지 않았습니다 (`docs/00-overview.md` 10장 참고).

## 지금 상태

0단계(기술 검증, PoC) 착수 전 단계입니다. 이 저장소에는 앱의 핵심 계산
로직(`CamZoomCore`)과 SwiftUI 화면의 1차 초안이 들어 있고, 실제 가상
카메라 기능(카메라 익스텐션)은 아직 비어 있습니다.

## 폴더 구조

```
.
├── docs/
│   ├── 00-overview.md       # 종합 문서 (여기부터 읽기)
│   ├── 01-product-plan.md   # 기획서
│   ├── 02-technical-design.md   # 기술 설계서
│   ├── 03-verification-plan.md  # 기술 검증 계획
│   └── verification/        # 검증 결과 보관
├── design/
│   └── screens/             # 화면 구성 와이어프레임 원본
├── Packages/
│   └── CamZoomCore/         # 앱·익스텐션이 공용으로 쓰는 순수 계산 로직 (Swift Package)
│       ├── Sources/CamZoomCore/
│       │   ├── AspectOption.swift   # 자르기 비율 (원본/정사각형/4:3/16:9)
│       │   ├── CropState.swift      # 사용자 설정 모델 + 저장/불러오기
│       │   ├── CropMath.swift       # 확대·위치 → 실제 잘라낼 좌표 계산
│       │   └── FrameProcessor.swift # Core Image로 실제 프레임을 잘라서 확대
│       └── Tests/CamZoomCoreTests/  # 위 계산 로직의 단위 테스트
├── App/
│   └── CamZoom/             # 호스트 앱 (SwiftUI + AVFoundation), 아직 Xcode 타깃 미생성
│       ├── CamZoomApp.swift
│       └── CameraManager.swift
└── Extension/
    └── README.md            # 카메라 익스텐션 타깃을 Xcode로 만드는 방법 (자리표시자)
```

기술 설계서 4장의 모듈 구조와는 아직 다릅니다. 맞추기 위해 고칠 부분은
`docs/00-overview.md` 11장에 정리돼 있습니다.

## 시작하는 방법 (맥에서, Xcode 필요)

이 저장소의 `.swift` 파일은 작성돼 있지만, 아직 `.xcodeproj`가 없습니다.
Xcode 프로젝트 생성은 로컬 파일 시스템 조작이 많아 Xcode에서 직접 하는
편이 안전합니다.

1. Xcode에서 `File > New > Project > macOS > App`으로 `CamZoom` 앱
   타깃을 만듭니다. Interface는 SwiftUI를 선택합니다.
2. 자동 생성된 `CamZoomApp.swift`, `ContentView.swift`를 지우고, 이
   저장소의 `App/CamZoom/*.swift` 두 파일을 프로젝트에 끌어다 넣습니다.
3. `File > Add Package Dependencies... > Add Local...`로
   `Packages/CamZoomCore`를 앱 타깃에 추가합니다.
4. 타깃의 **Signing & Capabilities**에서 App Sandbox의 **Camera**를
   체크합니다.
5. **Info** 탭에 `Privacy - Camera Usage Description`을 추가합니다.
6. ⌘R로 실행해서 원본 미리보기, 위치 지정 확대, 비율 선택이 동작하는지
   확인합니다.
7. 카메라 익스텐션 타깃은 `Extension/README.md`의 안내를 따라 별도로
   생성합니다.

## CamZoomCore만 따로 테스트하기 (Xcode 없이도 가능)

`Packages/CamZoomCore`는 Swift Package라서, Swift 툴체인이 있는 맥에서는
Xcode 프로젝트 없이도 계산 로직만 검증할 수 있습니다.

```bash
cd Packages/CamZoomCore
swift test
```

## 문서

- [`docs/00-overview.md`](docs/00-overview.md) — 종합 문서
- [`docs/01-product-plan.md`](docs/01-product-plan.md) — 기획서
- [`docs/02-technical-design.md`](docs/02-technical-design.md) — 기술 설계서
- [`docs/03-verification-plan.md`](docs/03-verification-plan.md) — 기술 검증 계획
- [`Extension/README.md`](Extension/README.md) — 카메라 익스텐션 타깃 생성 안내
