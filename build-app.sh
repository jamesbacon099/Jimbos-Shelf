#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")" && pwd)"
output="$project/../outputs"
mkdir -p "$output"
stage="$(mktemp -d "$output/.shelf.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Jimbo's Shelf.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/Tools"
cp "$project/Info.plist" "$bundle/Contents/"
cp -R "$project/Licenses" "$bundle/Contents/Resources/"
cp "$project/LICENSE" "$bundle/Contents/Resources/LICENSE.txt"
for tool in yt-dlp deno ffmpeg ffprobe; do
    test -x "$project/.tools/$tool"
    cp "$project/.tools/$tool" "$bundle/Contents/Resources/Tools/"
done
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.2" \
    -module-cache-path "$output/.sample-shelf-cache" "$project"/*.swift -o "$bundle/Contents/MacOS/SampleShelf"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
ditto -c -k --keepParent "$bundle" "$stage/Jimbos-Shelf-macOS-arm64.zip"
unzip -tq "$stage/Jimbos-Shelf-macOS-arm64.zip"
ditto "$bundle" "$output/Jimbo's Shelf.app"
mv -f "$stage/Jimbos-Shelf-macOS-arm64.zip" "$output/Jimbos-Shelf-macOS-arm64.zip"
