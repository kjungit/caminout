# CamZoomExtension (카메라 익스텐션)

Core Media I/O 카메라 익스텐션. 호스트 앱이 처리한 프레임을 받아 화상 앱에 일반
카메라처럼 내보내기만 합니다 (기술 설계서 2·6장, ADR-02). 영상 처리 로직은 없고,
**CamZoomShared 패키지 하나만 의존**합니다. 그래서 효과·자르기 코드를 고쳐도
익스텐션을 다시 설치할 필요가 없습니다.

## 구성

| 파일 | 역할 |
| --- | --- |
| `main.swift` | 진입점. provider 서비스를 시작한다 |
| `ExtensionProviderSource.swift` | 장치 하나를 등록한다 |
| `ExtensionDeviceSource.swift` | 장치, sink → source 전달, 안내 화면, 사용자 정의 속성 |
| `StreamSources.swift` | source 스트림(화상 앱이 읽음), sink 스트림(앱이 넣음) |
| `Info.plist` | `CMIOExtensionMachServiceName` = 팀 접두어 + 번들 ID |
| `CamZoomExtension.entitlements` | 샌드박스, App Group |

## 동작

- 장치 하나에 스트림 두 개: **source**(화상 앱용), **sink**(호스트 앱용).
- 출력 형식은 1920×1080, 1280×720, 1080×1080을 30fps로 광고하고, 실제 형식은 화상 앱이 고릅니다.
- source나 sink가 열려 있으면 30fps 타이머가 돕니다. 매 틱마다 sink에서 프레임을 꺼내고,
  밀려 있으면 가장 최근 프레임만 source로 보냅니다(지연이 쌓이지 않게).
- 1초 동안 sink에서 프레임이 오지 않으면 "앱을 실행해 주세요" 안내 화면을 보냅니다 (A5).
- 앱은 아래 사용자 정의 장치 속성을 읽습니다 (`CamZoomShared.CustomProperty`).

| 속성 | 값 | 용도 |
| --- | --- | --- |
| `cact` | "1"/"0" | 화상 앱이 source를 쓰는 중인지 → 앱이 카메라를 켜고 끔 (G3) |
| `cpvr` | "1" | 앱↔익스텐션 프로토콜 버전 → 다르면 앱이 교체 요청 (G5) |
| `cafm` | "1920x1080" | 화상 앱이 고른 형식 → 앱이 합성 크기를 맞춤 |
| `cbld` | 빌드 번호 | 진단용 |

## 바꿀 때 주의

- 장치·스트림 ID(`CameraIdentity`)는 첫 출시 후 절대 바꾸지 않습니다 (G8). 화상 앱이 이 값으로 카메라를 기억합니다.
- 속성의 의미나 sink 규칙을 바꾸면 `CameraIdentity.protocolVersion`을 올립니다.
- 시스템 확장은 빌드 번호(CFBundleVersion)가 올라가야 교체됩니다. `scripts/install-dev.sh`가 매번 올립니다 (G16).
- 로그 보기: `log stream --predicate 'subsystem == "com.kjungit.caminout.extension"'`

## 참고

- [Apple: Creating a camera extension with Core Media I/O](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o)
- [Apple WWDC22: Create camera extensions with Core Media IO](https://developer.apple.com/videos/play/wwdc2022/10022/)
- [Apple 개발자 포럼: 앱에서 CMIO 익스텐션으로 프레임 보내기](https://developer.apple.com/forums/thread/706184?page=2)
