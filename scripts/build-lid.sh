#!/bin/bash
# Build this direct-distribution fork without changing the upstream Xcode project.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_dir/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
xcodebuild -project "$repo_dir/src/Caffeine.xcodeproj" -scheme Caffeine \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$repo_dir/.build/lid" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    ENABLE_APP_SANDBOX=NO PRODUCT_BUNDLE_IDENTIFIER=net.ziyad.caffeine.lid \
    CODE_SIGNING_ALLOWED=NO build
app="$output_dir/Caffeine Lid.app"
if [ -e "$app" ]; then
    echo "Output already exists: $app. Choose an empty output directory." >&2
    exit 1
fi
ditto "$repo_dir/.build/lid/Build/Products/Release/Caffeine.app" "$app"
# A local build is ad-hoc signed, not Developer ID signed or notarized.
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_dir/Caffeine-Lid-macOS.zip"
echo "Built: $output_dir/Caffeine-Lid-macOS.zip"
