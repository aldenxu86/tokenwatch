#!/bin/zsh
# ============================================================
# TokenWatch 打包脚本:Release 构建 → .dmg
# 用法:./build-release.sh
# 产物:dist/TokenWatch-<版本>.dmg
# 注意:未签名构建,分发到其他 Mac 后需绕过 Gatekeeper:
#   方式1(推荐):右键 App → 打开
#   方式2:终端执行 xattr -dr com.apple.quarantine /Applications/TokenWatch.app
# ============================================================
set -e
cd "$(dirname "$0")"

echo "▶ Release 构建..."
xcodebuild -project TokenWatch.xcodeproj -scheme TokenWatch \
  -configuration Release build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build | tail -2

APP="build/Build/Products/Release/TokenWatch.app"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.2.1")
DMG="dist/TokenWatch-${VERSION}.dmg"

mkdir -p dist
rm -f "$DMG"
echo "▶ 制作 $DMG ..."
hdiutil create -volname "TokenWatch" -srcfolder "$APP" -ov -format UDZO "$DMG" | tail -1
echo "✅ 打包完成: $DMG"
