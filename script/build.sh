#!/bin/bash
set -euo pipefail
POMODORO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POMODORO_WORK="${POMODORO_WORK_ROOT:-$POMODORO_ROOT/.build-work}"
POMODORO_CONFIGURATION="${POMODORO_BUILD_CONFIGURATION:-release}"
case "$POMODORO_CONFIGURATION" in release|debug) ;; *) printf 'Use release or debug for POMODORO_BUILD_CONFIGURATION\n' >&2; exit 2;; esac
POMODORO_BUNDLE="$POMODORO_ROOT/plugins/pomodoro-notch/native/Pomodoro Notch.app"
mkdir -p "$POMODORO_WORK"
swift build -c "$POMODORO_CONFIGURATION" --package-path "$POMODORO_ROOT" --scratch-path "$POMODORO_WORK/build"
POMODORO_BIN="$(swift build -c "$POMODORO_CONFIGURATION" --package-path "$POMODORO_ROOT" --scratch-path "$POMODORO_WORK/build" --show-bin-path)/PomodoroNotch"
mkdir -p "$POMODORO_BUNDLE/Contents/MacOS" "$POMODORO_BUNDLE/Contents/Resources"
# Keep a running build's executable inode intact while staging the next build.
if [ -f "$POMODORO_BUNDLE/Contents/MacOS/PomodoroNotch" ]; then
    mkdir -p "$POMODORO_WORK/prior-binaries"
    POMODORO_PREVIOUS="$(mktemp -d "$POMODORO_WORK/prior-binaries/build.XXXXXX")"
    mv "$POMODORO_BUNDLE/Contents/MacOS/PomodoroNotch" "$POMODORO_PREVIOUS/PomodoroNotch"
fi
cp "$POMODORO_BIN" "$POMODORO_BUNDLE/Contents/MacOS/PomodoroNotch"
cat > "$POMODORO_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PomodoroNotch</string>
<key>CFBundleIdentifier</key><string>com.zoeysandel.pomodoro-notch</string>
<key>CFBundleName</key><string>Pomodoro Notch</string>
<key>CFBundleDisplayName</key><string>Pomodoro Notch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.4</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$POMODORO_BUNDLE"
/usr/bin/codesign --verify --strict "$POMODORO_BUNDLE"
printf 'Built %s\n' "$POMODORO_BUNDLE"
