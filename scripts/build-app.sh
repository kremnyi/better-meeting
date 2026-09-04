#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
package_dir=${script_dir:h}
build_dir="$package_dir/.build"
app_dir="$package_dir/dist/Better Meeting.app"
iconset_dir="$build_dir/BetterMeeting.iconset"
signing_identity=${BETTER_MEETING_SIGNING_IDENTITY:--}

if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/module-cache"

swift build \
    --package-path "$package_dir" \
    --scratch-path "$build_dir" \
    --cache-path "$build_dir/cache" \
    --config-path "$build_dir/config" \
    --security-path "$build_dir/security" \
    -c release \
    --product BetterMeeting

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$package_dir/App/Info.plist" "$app_dir/Contents/Info.plist"
cp "$build_dir/release/BetterMeeting" "$app_dir/Contents/MacOS/BetterMeeting"
cp "$package_dir/Assets/AppIconMaster.png" "$app_dir/Contents/Resources/AppIconMaster.png"

rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"
sips -z 16 16 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_16x16.png" >/dev/null
sips -z 32 32 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_32x32.png" >/dev/null
sips -z 64 64 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_128x128.png" >/dev/null
sips -z 256 256 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_256x256.png" >/dev/null
sips -z 512 512 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$package_dir/Assets/AppIconMaster.png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/BetterMeeting.icns"

sips -z 18 18 "$package_dir/Assets/MenuBarIconTemplate.png" \
    --out "$app_dir/Contents/Resources/MenuBarIconTemplate.png" >/dev/null
sips -z 36 36 "$package_dir/Assets/MenuBarIconTemplate.png" \
    --out "$app_dir/Contents/Resources/MenuBarIconTemplate@2x.png" >/dev/null
cp "$package_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
cp "$package_dir/NOTICE" "$app_dir/Contents/Resources/NOTICE.txt"
cp "$package_dir/ThirdPartyNotices.md" "$app_dir/Contents/Resources/ThirdPartyNotices.md"
cp "$build_dir/checkouts/argmax-oss-swift/LICENSE" "$app_dir/Contents/Resources/Argmax-LICENSE.txt"
cp "$build_dir/checkouts/argmax-oss-swift/NOTICES" "$app_dir/Contents/Resources/Argmax-NOTICES.txt"

codesign --force --deep --sign "$signing_identity" "$app_dir"

if [[ "$signing_identity" == "-" ]]; then
    echo "Warning: ad-hoc signing changes the app identity after every rebuild; Screen Recording access must then be granted again." >&2
fi

echo "$app_dir"
