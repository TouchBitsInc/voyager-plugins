#!/bin/zsh
# Builds the Media Plugin for release: archived, signed with the team's
# Developer ID — the app and every program in the yt-dlp it brings —
# notarized, stapled, and packed in a DMG to download; with the Sparkle
# appcast that tells installed plugins about it.
#
# Each release needs CURRENT_PROJECT_VERSION one higher in
# MediaPlugin.xcconfig: it's how Sparkle tells versions apart.
#
# Run it on the Mac that holds the Developer ID key (the CI Mac mini):
#
#   NOTARY_PROFILE=<keychain profile> Plugins/MediaPlugin/Scripts/release.sh
#
# The profile is made once with `xcrun notarytool store-credentials`.
# Or, with an App Store Connect API key instead:
#
#   NOTARY_KEY=<AuthKey.p8> NOTARY_KEY_ID=<id> NOTARY_ISSUER=<uuid> …/release.sh
#
# Other settings:
#   VERSION    the version to build, e.g. 0.2.1, over MediaPlugin.xcconfig's
#   BUILD      and its build number — as the release workflow sets them
#   IDENTITY   the signing identity; the team's Developer ID Application
#              certificate in the keychain unless named
#   NOTARIZE=0 everything but notarizing and stapling — to try the build
#              anywhere, with any identity
#
# Out, in Plugins/MediaPlugin/build/updates:
#   Voyager-Media-Plugin-<version>.dmg  the download
#   appcast.xml                         the update feed, signed with the
#                                       plugin's own Sparkle key in this
#                                       Mac's keychain — `voyager-media-plugin`,
#                                       made once with
#                                       `generate_keys --account voyager-media-plugin`;
#                                       not Sparkle's default one, which
#                                       another app's releases may use
# Both go up as assets of the GitHub release tagged <version>, which the
# feed URL in MediaPlugin.xcconfig and the appcast's links point at.
set -euo pipefail

TEAM=8Z3UH5979Z
here=${0:A:h}
root=${here:h}
build="$root/build"
notarize=${NOTARIZE:-1}

identity=${IDENTITY:-$(security find-identity -v -p codesigning | grep -o "\"Developer ID Application: [^\"]*($TEAM)\"" | head -1 | tr -d '"' || true)}
if [[ -z "$identity" ]]; then
  echo "error: no Developer ID Application identity for team $TEAM in the keychain (or name one in IDENTITY)" >&2
  exit 1
fi

notary=()
if [[ "$notarize" == 1 ]]; then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    notary=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  else
    echo "error: set NOTARY_PROFILE, or NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER — or NOTARIZE=0 to skip notarizing" >&2
    exit 1
  fi
fi

echo "==> Signing as: $identity"
rm -rf "$build"
mkdir -p "$build"

echo "==> Archiving"
xcodebuild archive \
  -project "$root/MediaPlugin.xcodeproj" \
  -scheme MediaPlugin \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$build/MediaPlugin.xcarchive" \
  -clonedSourcePackagesDirPath "$build/SourcePackages" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$identity" \
  DEVELOPMENT_TEAM=$TEAM \
  PROVISIONING_PROFILE_SPECIFIER= \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ${VERSION:+MARKETING_VERSION="$VERSION"} \
  ${BUILD:+CURRENT_PROJECT_VERSION="$BUILD"} \
  | grep -E "error:|warning: .*(sign|entitlement)|\*\* ARCHIVE" || true
app="$build/MediaPlugin.xcarchive/Products/Applications/Voyager Media Plugin.app"
[[ -d "$app" ]] || { echo "error: the archive has no app — see the build log above" >&2; exit 1; }

# Sparkle's helpers come signed by Sparkle, and Xcode re-signs only the
# framework around them: each is signed as ours, inside out, as Sparkle's
# documentation has it — then the framework, then the app, its
# entitlements kept.
echo "==> Signing Sparkle's helpers"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
resign() { codesign --force --sign "$identity" --options runtime --timestamp "$@"; }
resign "$sparkle/Versions/B/XPCServices/Installer.xpc"
resign --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
resign "$sparkle/Versions/B/Autoupdate"
resign "$sparkle/Versions/B/Updater.app"
resign "$sparkle"
resign --entitlements "$root/MediaPlugin/Resources/Config/MediaPlugin.entitlements" "$app"

version=$(defaults read "$app/Contents/Info" CFBundleShortVersionString)
name="Voyager-Media-Plugin-$version"
feed=$(defaults read "$app/Contents/Info" SUFeedURL)
publicKey=$(defaults read "$app/Contents/Info" SUPublicEDKey 2>/dev/null || true)

echo "==> Checking the signature"
codesign --verify --deep --strict --verbose=1 "$app"
# Every program in it, the bundled tools' included, as the app is.
find "$app" -type f -print0 | while IFS= read -r -d '' file; do
  [[ $(file -b "$file") == *Mach-O* ]] || continue
  if [[ $(codesign -dv "$file" 2>&1) != *"TeamIdentifier=$TEAM"* ]]; then
    echo "error: not signed by the team: $file" >&2; exit 1
  fi
done
echo "    every program in it is signed by $TEAM"
# The bundled yt-dlp runs as signed — under the hardened runtime.
"$app/Contents/Resources/Tools/yt-dlp/yt-dlp_macos" --version >/dev/null
echo "    yt-dlp $("$app/Contents/Resources/Tools/yt-dlp/yt-dlp_macos" --version) runs"

if [[ "$notarize" == 1 ]]; then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$app" "$build/$name.zip"
  xcrun notarytool submit "$build/$name.zip" "${notary[@]}" --wait
  xcrun stapler staple "$app"
  rm "$build/$name.zip"
fi

echo "==> Packing the DMG"
staging="$build/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Voyager Media Plugin.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Voyager Media Plugin" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$build/$name.dmg" >/dev/null
rm -rf "$staging"
codesign --sign "$identity" --timestamp "$build/$name.dmg"

if [[ "$notarize" == 1 ]]; then
  echo "==> Notarizing the DMG"
  xcrun notarytool submit "$build/$name.dmg" "${notary[@]}" --wait
  xcrun stapler staple "$build/$name.dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$build/$name.dmg"
fi

echo "==> Writing the appcast"
updates="$build/updates"
mkdir -p "$updates"
mv "$build/$name.dmg" "$updates/"
if [[ -z "$publicKey" ]]; then
  echo "    skipped: no SPARKLE_PUBLIC_KEY in MediaPlugin.xcconfig — run Sparkle's \`generate_keys --account voyager-media-plugin\` on this Mac once, and put the public key there"
else
  # Links to the release's own assets: <repo>/releases/download/<version>/.
  downloads="${feed%/latest/download/*}/download/$version/"
  "$build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    --account voyager-media-plugin --download-url-prefix "$downloads" "$updates"
  echo "    $updates/appcast.xml"
fi

echo "==> Done: $updates/$name.dmg"
