#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
CONFIGURATION=release
ARCHITECTURES=(arm64 x86_64)
for argument in "$@"; do
  case "$argument" in
    --debug) CONFIGURATION=debug ;;
    --native) ARCHITECTURES=("$(uname -m)") ;;
    *) echo "Usage: scripts/build.sh [--debug] [--native]" >&2; exit 2 ;;
  esac
done

APP_PATH="$PROJECT_ROOT/build/Wake Up Sunshine.app"
mkdir -p "$PROJECT_ROOT/build"
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
  SCRATCH_PATH="$PROJECT_ROOT/.build/app-$architecture"
  swift build --configuration "$CONFIGURATION" --arch "$architecture" --scratch-path "$SCRATCH_PATH" --product WakeUpSunshine
  BINARY_PATH="$(swift build --configuration "$CONFIGURATION" --arch "$architecture" --scratch-path "$SCRATCH_PATH" --show-bin-path)"
  BINARIES+=("$BINARY_PATH/WakeUpSunshine")
done

# Replace only this script's generated bundle, never application data.
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
if [ "${#BINARIES[@]}" -gt 1 ]; then
  /usr/bin/lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/WakeUpSunshine"
else
  cp "${BINARIES[0]}" "$APP_PATH/Contents/MacOS/WakeUpSunshine"
fi
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
swift scripts/make-icon.swift "$PROJECT_ROOT/build/AppIcon.iconset"
xcrun iconutil -c icns "$PROJECT_ROOT/build/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
# Ad-hoc signing makes the development bundle runnable on Apple Silicon.
# release.sh replaces this with a timestamped Developer ID signature.
codesign --force --sign - "$APP_PATH"
/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/WakeUpSunshine"
echo "Built: $APP_PATH"
