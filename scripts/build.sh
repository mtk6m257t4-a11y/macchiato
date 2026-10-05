#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
source_dir="${project_dir}/src"
output_dir="${project_dir}/dist"
app_dir="${output_dir}/Macchiato.app"
iconset="${output_dir}/AppIcon.iconset"
sdk_dir=${MACCHIATO_SDK:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path)}
module_cache="${output_dir}/module-cache"

mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources" "${iconset}" "${module_cache}"
cp "${source_dir}/Info.plist" "${app_dir}/Contents/Info.plist"

/usr/bin/xcrun swiftc -O -target arm64-apple-macosx13.0 -sdk "${sdk_dir}" \
    -module-cache-path "${module_cache}" \
    -framework AppKit "${source_dir}/Macchiato.swift" \
    -o "${app_dir}/Contents/MacOS/Macchiato"
/usr/bin/xcrun swiftc -O -target arm64-apple-macosx13.0 -sdk "${sdk_dir}" \
    -module-cache-path "${module_cache}" \
    "${source_dir}/render_app_icon.swift" \
    -o "${output_dir}/render_app_icon"
"${output_dir}/render_app_icon" "${output_dir}/AppIcon-1024.png"

make_icon() {
    /usr/bin/sips -z "$1" "$1" "${output_dir}/AppIcon-1024.png" \
        --out "${iconset}/$2" >/dev/null
}
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
cp "${output_dir}/AppIcon-1024.png" "${iconset}/icon_512x512@2x.png"
/usr/bin/python3 "${project_dir}/scripts/pack_icon.py" "${iconset}" \
    "${app_dir}/Contents/Resources/AppIcon.icns"

/usr/bin/xcrun clang -O2 -target arm64-apple-macosx13.0 -isysroot "${sdk_dir}" \
    "${source_dir}/MacchiatoHelper.c" \
    -o "${app_dir}/Contents/Resources/MacchiatoHelper"
/usr/bin/codesign --force --sign - -i local.codex.macchiato.helper \
    "${app_dir}/Contents/Resources/MacchiatoHelper"
/usr/bin/codesign --force --sign - "${app_dir}"
/usr/bin/codesign --verify --deep --strict "${app_dir}"

/usr/bin/ditto -c -k --keepParent "${app_dir}" "${output_dir}/Macchiato.zip"
echo "Built ${app_dir} and ${output_dir}/Macchiato.zip"
