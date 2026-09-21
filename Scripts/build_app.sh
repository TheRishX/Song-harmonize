#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
OUTPUT_ROOT="${1:-$PROJECT_ROOT/dist}"
APP_PATH="$OUTPUT_ROOT/Song Harmonize.app"

cd "$PROJECT_ROOT"
swift build --configuration release --build-system native
BIN_PATH="$(swift build --configuration release --build-system native --show-bin-path)"

mkdir -p "$OUTPUT_ROOT"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$BIN_PATH/SongHarmonize" "$APP_PATH/Contents/MacOS/SongHarmonize"

if [[ -d "$BIN_PATH/SongHarmonize_SongHarmonize.bundle" ]]; then
  ditto "$BIN_PATH/SongHarmonize_SongHarmonize.bundle" "$APP_PATH/Contents/Resources/SongHarmonize_SongHarmonize.bundle"
fi

# Ad-hoc signing is free and makes the local bundle internally consistent. It
# is not Apple notarization, so the first launch may still require Finder > Open.
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Built ad-hoc signed, unnotarized app: $APP_PATH"
echo "Run checks with: '$APP_PATH/Contents/MacOS/SongHarmonize' --self-check"
