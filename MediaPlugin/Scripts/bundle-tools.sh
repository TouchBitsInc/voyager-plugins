#!/bin/zsh
# Puts the plugin's tools in the app: each at the version tools.json pins,
# checked against the checksum its project publishes, and signed as the
# app is — every program and library in it, as notarization wants. A new
# tool version is a new plugin version: change tools.json, and ship.
#
# Downloads are kept in Plugins/MediaPlugin/.tools (not in git), so a
# build after the first needs no network.
set -euo pipefail

config="$SRCROOT/MediaPlugin/Resources/Config/tools.json"
cache="$SRCROOT/.tools"
tools="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Tools"
mkdir -p "$cache" "$tools"

# Already in the app as tools.json pins them, signed as this build signs:
# nothing to do. Anything else — a new version, another identity, a clean
# build — and it's all done again.
identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[[ "${CODE_SIGNING_ALLOWED:-YES}" == "YES" ]] || identity="unsigned"
stamp="$(shasum -a 256 "$config" "$0" | cut -d' ' -f1 | tr '\n' ' ')$identity $CONFIGURATION"
if [[ -f "$tools/.stamp" && "$(cat "$tools/.stamp")" == "$stamp" ]]; then
  echo "Tools up to date"
  exit 0
fi
rm -f "$tools/.stamp"

value() { plutil -extract "$1.$2" raw -o - "$config"; }

for name in $(plutil -convert json -o - "$config" | /usr/bin/python3 -I -c 'import json,sys; print(" ".join(json.load(sys.stdin)))'); do
  version=$(value "$name" version)
  url=$(value "$name" url)
  sha256=$(value "$name" sha256)
  archive="$cache/$name-$version.zip"
  unpacked="$cache/$name-$version"

  if [[ ! -f "$archive" ]] || [[ $(shasum -a 256 "$archive" | cut -d' ' -f1) != "$sha256" ]]; then
    echo "Downloading $name $version"
    curl -fsSL --retry 3 -o "$archive.part" "$url"
    mv "$archive.part" "$archive"
  fi
  actual=$(shasum -a 256 "$archive" | cut -d' ' -f1)
  if [[ "$actual" != "$sha256" ]]; then
    echo "error: $name $version's checksum is $actual, not $sha256 as tools.json says" >&2
    rm -f "$archive"
    exit 1
  fi
  if [[ ! -d "$unpacked" ]]; then
    ditto -x -k "$archive" "$unpacked.part"
    mv "$unpacked.part" "$unpacked"
  fi
  rsync -a --delete "$unpacked/" "$tools/$name/"
done

# A framework from a zip without symlinks (yt-dlp's Python.framework) has
# copies where its links belong — Versions/Current, and Python and
# Resources at its top — and codesign can't tell what it is. The links are
# put back.
find "$tools" -type d -name "*.framework" -prune -print0 | while IFS= read -r -d '' framework; do
  version=$(ls "$framework/Versions" | grep -vx Current | head -1)
  [[ -n "$version" ]] || continue
  rm -rf "$framework/Versions/Current"
  ln -s "$version" "$framework/Versions/Current"
  for item in "$framework/Versions/$version"/*; do
    rm -rf "$framework/${item:t}"
    ln -s "Versions/Current/${item:t}" "$framework/${item:t}"
  done
done
cp "$config" "$tools/tools.json"

# Signed as the app is, inside out: libraries before the programs that
# load them. An unsigned build leaves the tools as their projects signed
# them.
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  timestamp=(); [[ "$CONFIGURATION" == "Release" ]] && timestamp=(--timestamp)
  sign() { codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime $timestamp "$1"; }
  # Frameworks whole, as bundles; every other program or library alone.
  find "$tools" -type d -name "*.framework" -prune -print0 | while IFS= read -r -d '' framework; do
    sign "$framework/Versions/$(readlink "$framework/Versions/Current")"
  done
  find "$tools" -path "*.framework" -prune -o -type f -print0 | while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O"; then print -r -- "$file"; fi
  done | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2- | while IFS= read -r binary; do
    sign "$binary"
  done
fi

print -r -- "$stamp" > "$tools/.stamp"
