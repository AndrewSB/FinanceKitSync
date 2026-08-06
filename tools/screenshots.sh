#!/bin/bash
#
# Captures the five App Store screenshots at both required sizes.
#
# Everything on screen is synthetic — the app is launched with
# -FKSScreenshotScene, which seeds invented state (see
# app/FinanceKitSync/Support/ScreenshotMode.swift). No sync runs, FinanceKit is
# never queried, and no real transaction ever reaches an image.
#
# That seeding is `#if DEBUG`, so this builds and captures a Debug build. It
# renders identically to Release; the only difference is the presence of the
# seeding code.
#
#   ./tools/screenshots.sh            # build, capture, leave sims booted
#   KEEP_SIMS=0 ./tools/screenshots.sh  # shut the sims down afterwards
#
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="$PWD/build/screenshots"
DERIVED="$PWD/build/screenshot-derived"

# 6.9" and 6.5" are the two sizes App Store Connect requires for iPhone.
DEVICES=(
    "6.9in:FKS-6.9:com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
    "6.5in:FKS-6.5:com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max"
)
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-0"

# Order matters — this is the order they appear in the listing.
SCENES=(onboarding connect syncing settled settings)

BUNDLE_ID="com.asb.FinanceKitSync"

# Below this, a PNG at these dimensions is a blank window: the app is up but
# SwiftUI hasn't drawn its first frame, so all you get is white and a status
# bar. Real screens compress to 150 KB and up; blanks land around 75-88 KB.
# The gap is wide enough to be a reliable gate, and getting it wrong fails the
# run rather than silently uploading an empty screenshot to the App Store.
MIN_BYTES=120000

# Screenshots the simulator once the screen has actually rendered: two captures
# in a row that both carry real content. A fixed sleep raced the first frame and
# produced blanks on 4 of 10 shots.
#
# Deliberately *not* a test for two byte-identical frames, which is the obvious
# way to write this and is wrong here — the 'syncing' scene has a spinner, so
# its frames never repeat and the run stalled until it timed out.
capture() {
    local udid="$1" path="$2" scene="$3"
    local tmp="${path}.tmp.png" size=0 rendered=0

    for _ in $(seq 1 15); do
        sleep 2
        xcrun simctl io "$udid" screenshot --type=png "$tmp" >/dev/null 2>&1 || continue
        size=$(stat -f%z "$tmp")
        if [ "$size" -ge "$MIN_BYTES" ]; then
            rendered=$((rendered + 1))
            if [ "$rendered" -ge 2 ]; then
                mv "$tmp" "$path"
                return 0
            fi
        else
            # Went blank again — start counting over.
            rendered=0
        fi
    done

    rm -f "$tmp"
    echo "error: '$scene' never rendered — last capture was ${size} bytes" >&2
    exit 1
}

echo "==> Building Debug for simulator"
# Signed (ad-hoc, which is all the simulator needs) rather than
# CODE_SIGNING_ALLOWED=NO. An unsigned app can't reach the Keychain, so
# ServerConfig.setToken silently fails, isConfigured stays false, and every
# scene falls back to onboarding.
xcodebuild -project app/FinanceKitSync.xcodeproj -scheme FinanceKitSync \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -configuration Debug -derivedDataPath "$DERIVED" build >/dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/FinanceKitSync.app"
[ -d "$APP" ] || { echo "no app at $APP"; exit 1; }

# Guard against ever shipping these: a Release build has no ScreenshotMode, so
# if this string is missing the capture would silently produce empty screens.
# Searched across the bundle, not just the executable: Xcode's debug-dylib
# builds leave the actual code in FinanceKitSync.debug.dylib and the top-level
# binary is a stub.
if ! grep -qr FKSScreenshotScene "$APP" 2>/dev/null; then
    echo "error: built app has no screenshot mode — was it built Release?"
    exit 1
fi

for entry in "${DEVICES[@]}"; do
    IFS=: read -r label name devicetype <<<"$entry"

    udid=$(xcrun simctl list devices -j \
        | python3 -c "
import json,sys
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == '$name':
            print(d['udid']); raise SystemExit
")
    if [ -z "${udid:-}" ]; then
        echo "==> Creating simulator $name"
        udid=$(xcrun simctl create "$name" "$devicetype" "$RUNTIME")
    fi

    echo "==> $label ($name)"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null

    # The canonical Apple demo status bar, so the shots look deliberate.
    xcrun simctl status_bar "$udid" override \
        --time "9:41" --batteryState charged --batteryLevel 100 \
        --cellularMode active --cellularBars 4 --wifiBars 3 \
        --operatorName "" 2>/dev/null || true

    xcrun simctl install "$udid" "$APP"

    # Warm-up launch, discarded. The first launch after an install pays for
    # dyld caching the debug dylib and is by far the slowest.
    xcrun simctl launch "$udid" "$BUNDLE_ID" -FKSScreenshotScene settled >/dev/null
    sleep 8
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true

    mkdir -p "$OUT/$label"
    i=1
    for scene in "${SCENES[@]}"; do
        xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
        # Each scene is a fresh launch: the seeding runs once, at startup.
        xcrun simctl launch "$udid" "$BUNDLE_ID" -FKSScreenshotScene "$scene" >/dev/null

        path="$OUT/$label/$(printf '%d' $i)-$scene.png"
        capture "$udid" "$path" "$scene"

        echo "    $(basename "$path")  $(sips -g pixelWidth -g pixelHeight "$path" \
            | awk '/pixel/ {printf "%s ", $2}')"
        i=$((i + 1))
    done

    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    if [ "${KEEP_SIMS:-1}" = "0" ]; then
        xcrun simctl shutdown "$udid"
    fi
done

echo
echo "==> Wrote to $OUT"
