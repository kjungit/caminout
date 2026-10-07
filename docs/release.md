# 서명·공증·배포 준비

웹사이트 직접 배포(App Store 아님)를 기준으로 한다. 가상 카메라는 시스템 확장이라
Developer ID 서명과 애플 공증이 없으면 다른 맥에 설치되지 않는다 (기술 설계서 10장).

## 한 번만 하는 준비

1. Apple Developer Program 가입 (연 $99), Xcode > Settings > Accounts 로그인.
2. 인증서: **Developer ID Application** 인증서 발급 (Xcode > Accounts > Manage Certificates).
3. 식별자 등록 (developer.apple.com > Identifiers)
   - 앱 `com.kjungit.caminout`: System Extension 기능 켜기
   - 익스텐션 `com.kjungit.caminout.extension`
   - App Group `<팀 ID>.com.kjungit.caminout`은 macOS에서는 팀 접두어 형식이라 별도 등록이 필요 없다.
4. 프로비저닝 프로파일: 앱·익스텐션 각각 **Developer ID** 프로파일 발급.
5. 공증용 App Store Connect API 키 발급 (Users and Access > Integrations > App Store Connect API).

번들 ID와 가상 장치 UID(`CamZoomShared/CameraIdentity.swift`)는 첫 배포 후 바꿀 수 없다.
앱 이름을 정했으면 첫 배포 전에 함께 확정한다.

## GitHub 저장소 비밀값 (Settings > Secrets and variables > Actions)

| 이름 | 내용 |
| --- | --- |
| `TEAM_ID` | 10자리 팀 ID |
| `DEVELOPER_ID_P12` | Developer ID Application 인증서 .p12를 `base64`로 인코딩한 값 |
| `DEVELOPER_ID_P12_PASSWORD` | .p12 비밀번호 |
| `APP_PROVISIONING_PROFILE` | 앱 Developer ID 프로파일 base64 |
| `EXTENSION_PROVISIONING_PROFILE` | 익스텐션 Developer ID 프로파일 base64 |
| `ASC_API_KEY_P8` | App Store Connect API 키 .p8 내용 |
| `ASC_API_KEY_ID` | API 키 ID |
| `ASC_API_ISSUER_ID` | Issuer ID |

## 릴리스

1. `project.yml`의 `MARKETING_VERSION`을 올리고 `xcodegen generate` 후 커밋.
2. 같은 버전으로 태그: `git tag v0.1.0 && git push origin v0.1.0`
3. `Release` 워크플로가 아카이브 → 서명 → 공증 → 스테이플 → DMG(서명·공증) → GitHub Release까지 만든다.
4. 마지막 설치 확인은 개발에 쓰지 않은 맥이나 새 사용자 계정에서 한다 ([게이트 A6](verification/gate-a-b-checklist.md)).

## 나중에 할 것

- **Sparkle 2 자동 업데이트**: 업데이트 피드를 올릴 웹사이트가 생기면 넣는다. SPM으로 Sparkle을 추가하고,
  Info.plist에 `SUFeedURL`·`SUPublicEDKey`, 릴리스 워크플로에 `generate_appcast` 단계와 `SPARKLE_ED_PRIVATE_KEY` 비밀값을 더한다.
