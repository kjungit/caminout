# 화면 구성 (와이어프레임 원본)

동작하는 시안은 Claude 화면 구성 캔버스에서 볼 수 있습니다:
https://claude.ai/artifact/Dz6oxhHYSABb2ioHr3mbAc

이 폴더의 파일은 그 캔버스의 원본입니다. `*.dc.html`은 캔버스 전용 형식이라
브라우저에서 바로 열면 그대로 보이지 않습니다. 이미지나 PDF가 필요하면
캔버스에서 내보내기를 이용하세요.

| 파일 | 화면 |
| --- | --- |
| `MenuBarPopover.dc.html` | 메뉴바 팝오버 (통화 중 빠른 조작) |
| `MainWindow.dc.html` | 메인 창 (가운데 미리보기 + 오른쪽 설정 패널, 탭 4개) |
| `SettingsWindow.dc.html` | 설정 창 (입력 카메라, 출력 해상도, 단축키, 화면 모드) |
| `InstallGuide.dc.html` | 설치 안내 창 (5단계) |
| `*Dark.dc.html` | 위 4개 화면의 다크 모드 버전 |
| `shared.css` | 공통 스타일과 라이트·다크 색 변수 |
| `canvas.json` | 캔버스 배치 정보 |

화면 구성 설명은 `docs/00-overview.md` 4장에 있습니다.
