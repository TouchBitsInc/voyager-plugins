#!/bin/bash
# Builds every plugin in this checkout, team-signed, and installs it in
# /Applications, where Voyager finds and checks plugins: the way to run a
# Debug Voyager against the latest plugins.
#
#   Scripts/install-dev.sh            all plugins
#   Scripts/install-dev.sh Restyle    just one (by folder name, "Plugin" optional)
#
# Team-signed (Apple Development), as Voyager accepts any build signed by the
# team: an unsigned plugin is refused. Released copies already installed are
# moved aside once, to ~/Library/Caches/voyager-plugins/released/, so
#   Scripts/install-dev.sh --restore
# puts them back. Debug builds; each plugin's own release workflow makes the
# real ones.
set -euo pipefail
cd "$(dirname "$0")/.."

backups="$HOME/Library/Caches/voyager-plugins/released"
derived="$HOME/Library/Caches/voyager-plugins/DerivedData"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

plugins=()
for project in */*.xcodeproj; do plugins+=("$(dirname "$project")"); done

if [ "${1:-}" = "--restore" ]; then
  for backup in "$backups"/*.app; do
    [ -e "$backup" ] || { echo "No released copies to restore."; exit 0; }
    name=$(basename "$backup")
    echo "==> Restoring the released $name"
    pkill -x "${name%.app}" 2>/dev/null || true
    rm -rf "/Applications/$name"
    mv "$backup" "/Applications/$name"
  done
  exit 0
fi

if [ -n "${1:-}" ]; then
  wanted="${1%Plugin}Plugin"
  [ -d "$wanted" ] || { echo "error: no plugin '$1' (have: ${plugins[*]})" >&2; exit 1; }
  plugins=("$wanted")
fi

mkdir -p "$backups"
for plugin in "${plugins[@]}"; do
  echo "==> Building $plugin"
  xcodebuild -project "$plugin/$plugin.xcodeproj" -scheme "$plugin" -configuration Debug \
    -destination platform=macOS -derivedDataPath "$derived" -allowProvisioningUpdates \
    -quiet build
  # The built app whose bundle ID is the plugin's, from its manifest.
  id=$(plutil -extract id raw "$plugin/$plugin/Resources/manifest.json")
  app=""
  for candidate in "$derived/Build/Products/Debug"/*.app; do
    if [ "$(defaults read "$candidate/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$id" ]; then
      app=$candidate
    fi
  done
  [ -n "$app" ] || { echo "error: no built app for $plugin" >&2; exit 1; }
  name=$(basename "$app")

  # Signed by the team, or Voyager won't use it.
  codesign --verify --strict "$app"
  signature=$(codesign -dv "$app" 2>&1)
  [[ $signature == *"TeamIdentifier=8Z3UH5979Z"* ]] \
    || { echo "error: $name isn't signed by the team" >&2; exit 1; }

  installed="/Applications/$name"
  if [ -e "$installed" ] && [ ! -e "$backups/$name" ] \
     && [[ $(codesign -dv --verbose=2 "$installed" 2>&1) == *"Authority=Developer ID Application"* ]]; then
    echo "    keeping the released $name in $backups"
    mv "$installed" "$backups/$name"
  fi
  pkill -x "${name%.app}" 2>/dev/null || true
  rm -rf "$installed"
  ditto "$app" "$installed"
  # Only the installed copy known to macOS: Voyager asks it for every copy of
  # the plugin, and the build's, which the sandbox can't read, is noise.
  "$lsregister" -u "$app" 2>/dev/null || true
  rm -rf "$app"
  echo "    installed $installed ($(defaults read "$installed/Contents/Info" CFBundleShortVersionString))"
done

echo "Done. Voyager picks them up when it next comes to the front."
