#!/bin/zsh

set -euo pipefail

cd "${0:A:h:h}"
if [[ $(uname -m) != arm64 ]]; then
    echo "Release packaging requires an Apple Silicon Mac." >&2
    exit 1
fi

BETTER_MEETING_SIGNING_IDENTITY=- ./scripts/build-app.sh
app_dir="dist/Better Meeting.app"
codesign --verify --deep --strict "$app_dir"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
archive="Better-Meeting-${version}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "dist/$archive"
cd dist
shasum -a 256 "$archive" > "$archive.sha256"
cat "$archive.sha256"
