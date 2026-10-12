# CamZoom (가칭)

맥북 카메라를 조절하고, 꾸미고, 캐릭터로 바꿔서 Zoom·Discord·ZEP 등
모든 화상 서비스에 그대로 내보내는 맥 전용 무료 가상 카메라 앱.

모든 기획·설계 문서는 [`docs/`](docs/README.md)에 있습니다. 처음이라면
[`docs/00-overview.md`](docs/00-overview.md)(종합 문서)부터 읽어 주세요.

> 이름의 "Zoom"은 실제 화상회의 서비스와 혼동될 수 있어 정식 이름이
> 아닙니다. 이름이 정해지면 `CameraIdentity.productName` 한 곳과 앱 표시 이름만 바꿉니다.

## 지금 상태

0단계(기술 검증) 진행 중. 기술 설계서 4장 구조대로 패키지·앱·카메라 익스텐션이
들어 있고, 1단계 MVP 기능(위치 지정 확대, 비율, 반전·회전, 자동 저장, 가상 카메라)이
동작하는 상태까지 만들어져 있습니다. 실제 화상 앱 호환성·성능 검증(게이트 A·B)은
[`docs/verification/gate-a-b-checklist.md`](docs/verification/gate-a-b-checklist.md) 순서로 진행합니다.

## 폴더 구조

```
.
├── App/CamZoom/              # 호스트 앱 (SwiftUI 메뉴바 앱)
│   ├── AppState.swift        #   앱 상태, 설정 저장, 캡처 켜기·끄기
│   ├── Pipeline/             #   캡처 → 합성 → sink 출력, 미리보기
│   ├── System/               #   확장 설치·제거, 자동 실행, App Nap 방지
│   └── Views/                #   메뉴바 팝오버, 메인 창, 설정, 설치 안내
├── Extension/CamZoomExtension/  # CMIO 카메라 익스텐션 (sink → source 전달, 안내 화면)
├── Packages/
│   ├── CamZoomCore/          # 설정·프리셋 모델, 자르기 계산 (UI·미디어 의존 없음)
│   ├── CamZoomShared/        # 장치·스트림 ID, 출력 형식, 사용자 정의 속성, 안내 화면
│   ├── EffectsKit/           # 레이어 합성 엔진
│   ├── CaptureKit/           # 카메라 캡처, 검증용 가짜 입력
│   └── CameraBridge/         # 가상 카메라 sink 송신, 사용 중 감지
├── Config/                   # xcconfig (서명 팀은 Signing.local.xcconfig, 커밋 안 함)
├── project.yml               # XcodeGen 프로젝트 정의 → CamZoom.xcodeproj
├── scripts/install-dev.sh    # 개발 빌드를 /Applications에 설치·실행
├── tools/verification/       # 밀리초 시계, 색 막대, 결과 기록 양식
├── design/screens/           # 화면 구성 와이어프레임 원본
└── docs/                     # 기획·설계·검증 문서, 검증 결과
```

의존 방향: 앱 → 기능 패키지(EffectsKit·CaptureKit·CameraBridge) → 기반 패키지(CamZoomCore·CamZoomShared).
익스텐션은 CamZoomShared만 쓰므로 효과를 고쳐도 익스텐션을 다시 설치할 필요가 없습니다.

## 빌드

필요한 것: Xcode 16 이상(Swift 6), macOS 14 이상, [XcodeGen](https://github.com/yonaskolb/XcodeGen)(`brew install xcodegen`).

```bash
# 패키지 단위 테스트 (Xcode 프로젝트 없이도 가능)
for p in Packages/*; do (cd "$p" && swift test); done

# 서명 없이 빌드만 확인
xcodegen generate
xcodebuild -project CamZoom.xcodeproj -scheme CamZoom CODE_SIGNING_ALLOWED=NO build
```

`project.yml`을 고쳤으면 `xcodegen generate`로 프로젝트를 다시 만들고, 만들어진
`CamZoom.xcodeproj`도 함께 커밋합니다.

## 실제로 가상 카메라 띄우기

카메라 익스텐션은 시스템 확장이라 Apple Developer 계정으로 서명해야 하고, 앱이
`/Applications`에 있어야 설치됩니다.

1. Xcode > Settings > Accounts에서 Apple Developer 계정으로 로그인합니다.
2. `Config/Signing.local.xcconfig` 파일을 만들고 팀 ID를 적습니다.
   ```
   DEVELOPMENT_TEAM = XXXXXXXXXX
   ```
3. `scripts/install-dev.sh`를 실행합니다. 빌드 번호를 올려 빌드하고
   `/Applications/CamZoom.app`으로 복사한 뒤 실행합니다.
4. 설치 안내 창에서 카메라 권한 → 가상 카메라 설치 → 시스템 설정에서 허용 순서로 진행합니다.
5. QuickTime Player(새로운 동영상 녹화) 또는 화상 앱의 카메라 목록에서 **CamZoom Camera**를 고릅니다.

삭제는 앱 설정 > 가상 카메라 > "가상 카메라 제거"로 먼저 확장을 지운 뒤 앱을 휴지통에 넣습니다.

## 라이선스

코드는 [MIT 라이선스](LICENSE)입니다. 다음은 MIT 라이선스 대상이 아니며 저작권자가 모든 권리를 가집니다.

- 앱 이름, 앱 아이콘, 로고
- 기본 캐릭터, 스티커, 프레임 등 앱에 들어가는 그림·소리 자산

코드를 고쳐서 배포할 때는 다른 앱 이름과 아이콘, 다른 번들 ID·가상 장치 UID(`CamZoomShared/CameraIdentity.swift`)를 써 주세요.
같은 ID를 쓰면 사용자의 맥에서 이 앱의 가상 카메라와 충돌합니다.

## 문서

- [`docs/00-overview.md`](docs/00-overview.md) — 종합 문서
- [`docs/01-product-plan.md`](docs/01-product-plan.md) — 기획서
- [`docs/02-technical-design.md`](docs/02-technical-design.md) — 기술 설계서
- [`docs/03-verification-plan.md`](docs/03-verification-plan.md) — 기술 검증 계획
- [`docs/verification/gate-a-b-checklist.md`](docs/verification/gate-a-b-checklist.md) — 게이트 A·B 진행 절차
- [`docs/release.md`](docs/release.md) — 서명·공증·배포 준비
- [`Extension/README.md`](Extension/README.md) — 카메라 익스텐션 구조
