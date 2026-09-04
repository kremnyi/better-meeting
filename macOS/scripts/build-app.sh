#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
package_dir=${script_dir:h}
repo_dir=${package_dir:h}
build_dir="$package_dir/.build"
app_dir="$package_dir/dist/Better Meeting.app"

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
cp "$repo_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
cp "$repo_dir/NOTICE" "$app_dir/Contents/Resources/NOTICE.txt"
cp "$package_dir/ThirdPartyNotices.md" "$app_dir/Contents/Resources/ThirdPartyNotices.md"
cp "$build_dir/checkouts/argmax-oss-swift/LICENSE" "$app_dir/Contents/Resources/Argmax-LICENSE.txt"
cp "$build_dir/checkouts/argmax-oss-swift/NOTICES" "$app_dir/Contents/Resources/Argmax-NOTICES.txt"

codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
