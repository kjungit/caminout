# 게이트 A·B 진행 절차

[기술 검증 계획](../03-verification-plan.md) 2장의 게이트 A·B 항목을 이 저장소의 앱으로
실제로 확인하는 순서다. 통과 기준은 검증 계획에 있는 값을 그대로 쓰고, 결과를 본 뒤에
바꾸지 않는다. 결과는 `tools/verification/results-template.csv` 양식으로
`docs/verification/gate-a/`, `gate-b/`에 남긴다.

## 준비

- [ ] Apple Developer 계정으로 Xcode 로그인, `Config/Signing.local.xcconfig`에 팀 ID
- [ ] `scripts/install-dev.sh`로 설치, 설치 안내 5단계 완료
- [ ] 측정 도구
  - 밀리초 시계: `tools/verification/ms-clock.html`을 브라우저로 연다
  - 색 막대: 앱 설정 > 카메라 > 입력 "색 막대 (검증용)", 또는 `swift tools/verification/make-color-bars.swift`
  - 프레임 번호: 앱 설정 > 검증·개발 > "출력에 프레임 번호 표시"
  - 측정값 오버레이: 앱 설정 > 검증·개발 > "미리보기에 측정값 표시" (fps, 합성 p50/p95, 앱 내부 지연, 버린 프레임, 풀 고갈)
- [ ] 로그: `log stream --predicate 'subsystem BEGINSWITH "com.kjungit.caminout"' --level info`
- [ ] 테스트용 새 사용자 계정 (A6)

## 게이트 A: 가상 카메라 기반

| ID | 절차 | 기록할 것 |
| --- | --- | --- |
| A1 | 프레임 번호 켜기 → QuickTime "새로운 동영상 녹화"에서 CamZoom Camera 선택 → 10분 녹화 → 녹화본에서 빠진 번호 세기 | 총 프레임, 누락 수, 누락률 (기준 1% 미만) |
| A2 | Zoom 앱, Discord 앱, Discord 웹(Chrome), ZEP(Chrome·Safari), Google Meet, FaceTime 각각에서 카메라 목록에 보이는지, 영상이 나오는지 | 앱별 표시 여부, 앱 재시작 필요 여부 (Zoom·ZEP·Discord 중 하나라도 실패면 출시 보류 판단) |
| A3 | 각 화상 앱에서 형식을 바꿔 가며 확인 (앱 설정 화면의 "출력 해상도"에 화상 앱이 고른 형식이 보인다) | 1280×720, 1920×1080, 1080×1080 각각 잘림·여백·거부 여부 |
| A4 | 화상 앱에서 카메라를 켰다 끄기 10회. 메뉴바 아이콘(video.fill)·카메라 표시등 변화 확인. 로그의 `sourceActive`와 `runningSomewhere` 비교 | 켜짐·꺼짐 감지 시간(기준 1초 이내), 두 방식의 차이 |
| A5 | 화상 앱에서 영상이 나오는 중에 `killall CamZoom` → 안내 화면 전환 시간 → 앱 다시 실행 → 복구 시간 | 전환 시간(기준 1초 이내), 복구 시간(기준 3초 이내) |
| A6 | 서명·공증 빌드로 새 사용자 계정에서: 설치 → 승인 → 화상 앱에 보이기까지 시간, 앱 재시작 필요 여부, 빌드 번호 올린 버전으로 교체, 앱 설정 "가상 카메라 제거" 후 `systemextensionsctl list`에 남는지, 휴지통 삭제 후 남는지 | 단계별 결과, macOS 버전 (기준: 설치 5분 이내, 제거 후 잔존 0) |
| A7 | 앱 설정 > 가상 카메라 > 버전 표시 확인. `CameraIdentity.protocolVersion`을 올린 앱 빌드로 실행해 교체 요청이 뜨는지 | 감지 시간(기준 3초 이내) |

## 게이트 B: 파이프라인 성능·안정성 (M1 기준)

| ID | 절차 | 기록할 것 |
| --- | --- | --- |
| B1 | 밀리초 시계를 카메라로 비추고, 화상 앱 미리보기 속 시계와 실제 시계를 한 스크린샷에 담기 × 20회. 보조로 측정값 오버레이의 "앱 내부 지연" | 20회 값, 중앙값 (기준 100ms 이하) |
| B2 | 확대+비율 켠 상태로 Instruments (Points of Interest의 `render` 구간) 300프레임, 또는 오버레이 p95 | 합성 p50/p95 (기준 p95 12ms 이하) |
| B3 | 조절 모드로 화상 앱 30분, Instruments Energy·Time Profiler 또는 `sudo powermetrics` | 평균 CPU % (기준 10% 이하) |
| B4 | 모든 창을 닫고 메뉴바만 남긴 채 30분, QuickTime 녹화로 프레임 번호 확인 | 누락률 (App Nap 방지가 켜져 있는지 로그 "App Nap 방지 시작") |
| B5 | 2시간 연속 출력, 10분마다 활동 모니터 메모리와 오버레이의 풀 고갈 수 | 메모리 증가량 (기준 50MB 미만), 풀 고갈 0회 |
| B6 | Zoom과 QuickTime이 동시에 쓰는 상태로 10분 | 누락률 (기준 1% 미만), 풀 고갈 수 |
| B7 | 입력을 "색 막대"로 두고 화상 앱 화면을 캡처해 디지털 색상 측정기로 8개 막대 값을 읽기 | 막대별 RGB 차이 (기준 채널당 8 이하) |
| B8 | macOS 비디오 효과(인물 모드, 센터 스테이지)를 켜고 출력 확인 | 동작 방식 메모 (통과 기준 없음) |

## 끝나면

- [ ] 결과 CSV와 스크린샷을 `docs/verification/gate-a/`, `gate-b/`에 저장
- [ ] [기술 검증 계획](../03-verification-plan.md) 5장 "1단계 착수 전" 체크리스트를 채움
- [ ] 실패 항목은 정해 둔 대안과 함께 기술 설계서 12장 ADR에 한 줄씩 추가
