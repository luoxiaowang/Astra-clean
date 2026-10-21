#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift build -c release --product Astra
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PROJECT_ROOT/dist/Astra.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Astra" "$APP/Contents/MacOS/Astra"
cp -R "$BIN_DIR/Astra_Astra.bundle" "$APP/Contents/Resources/"
ICONSET="$PROJECT_ROOT/.build/Astra.iconset"
mkdir -p "$ICONSET"
cp "$PROJECT_ROOT/assets/Astra-icon.png" "$PROJECT_ROOT/.build/astra-icon.png"
for SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$SIZE" "$SIZE" "$PROJECT_ROOT/.build/astra-icon.png" --out "$ICONSET/icon_"$SIZE"x"$SIZE".png" >/dev/null
    DOUBLE=$((SIZE * 2))
    /usr/bin/sips -z "$DOUBLE" "$DOUBLE" "$PROJECT_ROOT/.build/astra-icon.png" --out "$ICONSET/icon_"$SIZE"x"$SIZE"@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Astra.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Astra</string>
<key>CFBundleDisplayName</key><string>Astra</string>
<key>CFBundleIdentifier</key><string>local.astra.mac</string>
<key>CFBundleExecutable</key><string>Astra</string>
<key>CFBundleIconFile</key><string>Astra.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSDownloadsFolderUsageDescription</key><string>Astra 扫描下载目录中的安装包，并在你确认后移入废纸篓。</string>
<key>NSDesktopFolderUsageDescription</key><string>Astra 分析你选择的桌面文件夹的空间占用。</string>
<key>NSDocumentsFolderUsageDescription</key><string>Astra 分析你选择的文稿文件夹的空间占用。</string>
<key>NSHumanReadableCopyright</key><string>Astra · 独立实现 · 个人使用</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --strict "$APP"
printf '\n已构建：%s\n' "$APP"
