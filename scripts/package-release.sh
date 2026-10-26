#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${PULSE_WIFI_APP_PATH:-$PWD/build/Pulse WiFi.app}"
test -x "$app/Contents/MacOS/PulseWiFi"
test "$(lipo -archs "$app/Contents/MacOS/PulseWiFi")" = arm64
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Expected a numeric app version." >&2
    exit 1
fi
name="Pulse-WiFi-$version-AppleSilicon-Preview"
mkdir -p build
staging="$(mktemp -d "$PWD/build/.wifi-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/$name"
copy="$staging/$name/Pulse WiFi.app"
ditto --norsrc --noextattr --noacl "$app" "$copy"
ditto --norsrc --noextattr --noacl scripts/Release-ReadMe.txt "$staging/$name/ReadMe.txt"
strip -S "$copy/Contents/MacOS/PulseWiFi"
codesign --force --sign - "$copy"
codesign --verify --deep --strict "$copy"
if strings "$copy/Contents/MacOS/PulseWiFi" | /usr/bin/grep -E '/Users/[^/]+/|/private/var/folders/' > /dev/null; then
    echo "Package rejected: executable contains absolute developer paths." >&2
    exit 1
fi
ditto --norsrc --noextattr --noacl -c -k --keepParent "$staging/$name" "$PWD/build/$name.zip"
unzip -tq "build/$name.zip"
(
    cd build
    shasum -a 256 "$name.zip" > "$name.zip.sha256"
)
echo "Packaged build/$name.zip (locally signed preview, not notarized)"
