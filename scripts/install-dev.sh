#!/bin/bash
# 개발용 빌드 → /Applications 설치 → 실행 (기술 설계서 10.3).
#
# 시스템 확장은 앱이 /Applications에 있어야 활성화되고, 빌드 번호가 올라가야 교체된다 (G16).
# 그래서 매번 시각 기반 빌드 번호(단조 증가)로 빌드한다.
#
# 사용법: scripts/install-dev.sh [Debug|Release]
# 서명 팀은 Config/Signing.local.xcconfig 에 DEVELOPMENT_TEAM = XXXXXXXXXX 로 적어 둔다.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
DERIVED="build/DerivedData"
APP_NAME="CamZoom.app"
DEST="/Applications/$APP_NAME"

if ! grep -qs "DEVELOPMENT_TEAM *= *[A-Z0-9]" Config/Signing.local.xcconfig; then
  echo "Config/Signing.local.xcconfig 에 DEVELOPMENT_TEAM 이 없습니다. 서명 없이는 확장을 설치할 수 없습니다." >&2
  exit 1
fi

if command -v xcodegen >/dev/null; then
  xcodegen generate --quiet
fi

echo "▶︎ 빌드 ($CONFIG, 빌드 번호 $BUILD_NUMBER)"
xcodebuild \
  -project CamZoom.xcodeproj \
  -scheme CamZoom \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true

BUILT="$DERIVED/Build/Products/$CONFIG/$APP_NAME"
if [ ! -d "$BUILT" ]; then
  echo "빌드 실패: $BUILT 가 없습니다. xcodebuild 로그를 확인하세요." >&2
  exit 1
fi
codesign --verify --deep --strict "$BUILT"

echo "▶︎ 설치 → $DEST"
osascript -e 'tell application id "com.kjungit.caminout" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

echo "▶︎ 실행"
open "$DEST"
echo "완료. 빌드 번호 $BUILD_NUMBER"
