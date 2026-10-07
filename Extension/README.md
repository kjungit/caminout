# CamZoomExtension (카메라 익스텐션)

이 폴더는 자리표시자입니다. Core Media I/O 카메라 익스텐션은 Xcode가 제공하는
**"Camera Extension"** 템플릿의 보일러플레이트(스트림 소스/싱크 설정, provider,
enumeration 코드 등)로 시작해야 합니다. 손으로 처음부터 작성하면 애플 문서와
어긋나기 쉬우므로, 반드시 아래 순서로 Xcode에서 타깃을 생성한 뒤 이 폴더의
파일들을 그 타깃 안으로 옮겨서 채워 넣으세요.

## 타깃 만들기

1. `CamZoom.xcodeproj`를 Xcode에서 엽니다 (프로젝트 자체는 아직 생성 전이면
   `File > New > Project > macOS > App`으로 `CamZoom` 앱을 먼저 만드세요).
2. `File > New > Target...` → **Camera Extension** 템플릿을 선택합니다.
3. 타깃 이름을 `CamZoomExtension`으로 짓습니다.
4. 번들 ID는 앱 번들 ID로 시작해야 합니다.
   예: 앱 `com.example.camzoom` → 익스텐션 `com.example.camzoom.extension`
   (기획서 9.2 식별자와 권한 참고).
5. 생성된 타깃에 `CamZoomCore` 패키지를 의존성으로 추가합니다
   (`Packages/CamZoomCore`를 로컬 패키지로 추가).

## 채워 넣을 부분

Xcode 템플릿이 만들어 주는 provider 코드 안에서, 카메라 프레임을 실제로
처리하는 부분을 다음처럼 `CamZoomCore`로 연결합니다.

- 앱에서 넘어온 원본 프레임을 받는 지점 → `CamZoomCore.FrameProcessor.process(_:state:)` 호출
- 현재 설정값(`CropState`) → App Group을 통해 앱과 공유 (기획서 9.2)
- 호스트 앱이 꺼져 있을 때 → 안내 화면 이미지를 대신 내보냄 (기획서 10장 예외 상황 처리)

## 참고 문서

- [Apple: Creating a camera extension with Core Media I/O](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o.md)
- [Apple WWDC22: Create camera extensions with Core Media IO](https://developer.apple.com/videos/play/wwdc2022/10022/)

세부 배경은 `docs/02-technical-design.md`의 4장(모듈 구조), 6장(앱↔익스텐션 통신), 10장(빌드·서명·배포)과 `docs/01-product-plan.md`의 9장(개발 환경과
프로젝트 구조), 10장(예외 상황 처리)을 참고하세요.
