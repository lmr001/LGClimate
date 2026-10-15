#!/bin/zsh
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/LG Climate.app"
for ARCH in arm64 x86_64; do
  swift build -c release --product LGClimate --triple "$ARCH-apple-macosx14.0" --scratch-path ".build/distribution-$ARCH"
done
ARM_BIN="$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build/distribution-arm64 --show-bin-path)/LGClimate"
INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build/distribution-x86_64 --show-bin-path)/LGClimate"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/LGClimate"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
codesign --force --sign "${LGCLIMATE_CODESIGN_IDENTITY:--}" --identifier com.lanceroberts.LGClimate "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
