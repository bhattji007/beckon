#!/usr/bin/env bash
# Beckon release builder: build -> sign -> zip + dmg -> notarize -> staple -> appcast -> checksums.
#
# Usage:  release/release.sh            (from anywhere; paths are resolved relative to this file)
#
# Environment (all optional):
#   BECKON_SIGN_IDENTITY     "Developer ID Application: Your Name (TEAMID)". Unset => ad-hoc signature + loud warning.
#   BECKON_NOTARY_PROFILE    notarytool keychain profile name (see `xcrun notarytool store-credentials`). Unset => no notarization.
#   BECKON_NOTARY_KEYCHAIN   path of the keychain file holding that profile (CI uses a temporary keychain). Default: login keychain.
#   BECKON_DOWNLOAD_BASE     where the dmg will be hosted; used for appcast.json. Default: https://beckon.shubham.club/releases
#   BECKON_SKIP_BUILD=1      reuse app/build/Beckon.app instead of running app/build.sh.
#
# Outputs (all in <repo>/dist, overwritten on every run):
#   Beckon-<version>.dmg   Beckon-<version>.zip   appcast.json   _redirects   SHA256SUMS.txt
set -euo pipefail

# ---------- helpers ----------------------------------------------------------------------------
if [[ -t 1 ]]; then BOLD=$'\e[1m'; RED=$'\e[31m'; YEL=$'\e[33m'; GRN=$'\e[32m'; DIM=$'\e[2m'; RST=$'\e[0m'
else BOLD=""; RED=""; YEL=""; GRN=""; DIM=""; RST=""; fi
step() { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RST"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s%s!!  %s%s\n' "$BOLD" "$YEL" "$*" "$RST" >&2; }
die()  { printf '\n%s%sERROR: %s%s\n' "$BOLD" "$RED" "$1" "$RST" >&2; shift; for l in "$@"; do printf '       %s\n' "$l" >&2; done; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH." "${2:-}"; }

# JSON-escape a string (stdin -> stdout, no surrounding quotes). Prefers jq / python3, falls back to sed.
json_escape() {
  if command -v jq >/dev/null 2>&1; then jq -Rs '.' | sed -e 's/^"//' -e 's/"$//'
  elif command -v python3 >/dev/null 2>&1; then python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'
  else sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'
  fi
}

# ---------- locate things -----------------------------------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP_SRC_DIR="$ROOT/app"
BUILD_APP="$APP_SRC_DIR/build/Beckon.app"
PLIST="$APP_SRC_DIR/Info.plist"
ENTITLEMENTS="$HERE/Beckon.entitlements"
NOTES_FILE="$HERE/NOTES.md"
DIST="$ROOT/dist"
STAGE="$DIST/.stage"            # scratch space inside dist so a plain `rm -rf dist` cleans everything
APP="$STAGE/Beckon.app"
DOWNLOAD_BASE="${BECKON_DOWNLOAD_BASE:-https://beckon.shubham.club/releases}"
DOWNLOAD_BASE="${DOWNLOAD_BASE%/}"

[[ "$(uname -s)" == "Darwin" ]] || die "This script only runs on macOS (needs codesign/hdiutil/notarytool)."
need xcrun "Install the Xcode Command Line Tools: xcode-select --install"
need codesign; need hdiutil; need ditto; need shasum
[[ -f "$PLIST" ]] || die "Info.plist not found at $PLIST"
[[ -f "$ENTITLEMENTS" ]] || die "Entitlements file missing: $ENTITLEMENTS"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
[[ -n "$VERSION" ]] || die "Could not read CFBundleShortVersionString from $PLIST"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || die "Version '$VERSION' is not semver (expected e.g. 0.9.0). Fix CFBundleShortVersionString in app/Info.plist."
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :BeckonUpdateFeedURL' "$PLIST" 2>/dev/null || true)"

DMG="$DIST/Beckon-$VERSION.dmg"
ZIP="$DIST/Beckon-$VERSION.zip"
APPCAST="$DIST/appcast.json"
SUMS="$DIST/SHA256SUMS.txt"
VOLNAME="Beckon $VERSION"

SIGN_IDENTITY="${BECKON_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${BECKON_NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${BECKON_NOTARY_KEYCHAIN:-}"
SIGNED=0; NOTARIZED=0

printf '%sBeckon release %s%s  %s(%s)%s\n' "$BOLD" "$VERSION" "$RST" "$DIM" "$BUNDLE_ID" "$RST"

# ---------- 1. build ------------------------------------------------------------------------------
step "Build"
if [[ "${BECKON_SKIP_BUILD:-0}" == "1" ]]; then
  info "BECKON_SKIP_BUILD=1, reusing $BUILD_APP"
else
  [[ -x "$APP_SRC_DIR/build.sh" ]] || die "app/build.sh not found or not executable."
  (cd "$APP_SRC_DIR" && ./build.sh)
fi
[[ -d "$BUILD_APP" ]] || die "Build did not produce $BUILD_APP"
[[ -x "$BUILD_APP/Contents/MacOS/Beckon" ]] || die "Main executable missing in $BUILD_APP"

mkdir -p "$DIST"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$BUILD_APP" "$APP"                      # work on a copy; never touch app/build in place
xattr -cr "$APP" 2>/dev/null || true           # resource forks / quarantine bits break codesign
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || die "Built app reports version $BUILT_VERSION but app/Info.plist says $VERSION. Rebuild without BECKON_SKIP_BUILD."
info "staged $APP"
info "architectures: $(lipo -archs "$APP/Contents/MacOS/Beckon" 2>/dev/null || echo unknown)"

# ---------- 2. sign -------------------------------------------------------------------------------
step "Sign"
if [[ -n "$SIGN_IDENTITY" ]]; then
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGN_IDENTITY"; then
    die "Signing identity not found in any keychain: $SIGN_IDENTITY" \
        "List what you have with:   security find-identity -v -p codesigning" \
        "It must be a 'Developer ID Application: ...' certificate (not 'Apple Development'). See DISTRIBUTION.md."
  fi
  case "$SIGN_IDENTITY" in
    *"Developer ID Application"*) ;;
    *) warn "'$SIGN_IDENTITY' is not a Developer ID Application certificate; Gatekeeper will not accept it outside this Mac." ;;
  esac
  COMMON=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
  # Inside-out: nested executables first, then the bundle (Apple's recommendation instead of --deep).
  find "$APP/Contents" -type f \( -perm -u+x -o -name '*.dylib' \) ! -path "$APP/Contents/MacOS/Beckon" -print0 \
    | while IFS= read -r -d '' f; do
        info "signing $(basename "$f")"
        codesign "${COMMON[@]}" --identifier "$BUNDLE_ID.$(basename "$f")" --entitlements "$ENTITLEMENTS" "$f"
      done
  info "signing Beckon.app"
  codesign "${COMMON[@]}" --entitlements "$ENTITLEMENTS" "$APP"
  SIGNED=1
else
  warn "BECKON_SIGN_IDENTITY is not set: AD-HOC SIGNING."
  warn "The resulting app is NOT distributable: Gatekeeper on other Macs will say it can't be verified"
  warn "and users must use System Settings > Privacy & Security > Open Anyway. For a real release set"
  warn "  export BECKON_SIGN_IDENTITY='Developer ID Application: <Name> (<TEAMID>)'  (see DISTRIBUTION.md)"
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
if [[ $SIGNED -eq 1 ]]; then
  info "$(codesign -dvv "$APP" 2>&1 | grep -E '^(Authority=Developer ID|TeamIdentifier|Timestamp)' | tr '\n' ';' | sed 's/;/; /g')"
fi

# ---------- 3. notarize the app (so the copy inside the dmg can be stapled) -----------------------
NOTARY_ARGS=()
notarize() {  # notarize <file> <label>
  local file="$1" label="$2" out id status
  info "submitting $label to Apple notary service (this can take a few minutes)…"
  if ! out="$(xcrun notarytool submit "$file" "${NOTARY_ARGS[@]}" --wait --timeout 30m 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    die "notarytool submit failed for $label." \
        "If it says the profile/credentials are missing, create them once with:" \
        "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>" \
        "(App Store Connect > Users and Access > Integrations > App Store Connect API; role Developer or Admin.)" \
        "Or with an Apple ID + app-specific password:" \
        "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id you@example.com --team-id TEAMID --password <app-specific-password>"
  fi
  printf '%s\n' "$out" | sed 's/^/    /'
  id="$(printf '%s\n' "$out" | awk '/^  id:/{print $2; exit}')"
  status="$(printf '%s\n' "$out" | awk '/status:/{s=$2} END{print s}')"
  if [[ "$status" != "Accepted" ]]; then
    [[ -n "$id" ]] && { info "fetching notary log for $id…"; xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" 2>&1 | sed 's/^/    /' >&2 || true; }
    die "Notarization of $label ended with status '${status:-unknown}' (expected Accepted)." \
        "Common causes: not signed with Developer ID, hardened runtime missing, no secure timestamp, or an unsigned nested binary." \
        "The log above lists each offending file."
  fi
}

step "Notarize"
if [[ -n "$NOTARY_PROFILE" ]]; then
  [[ $SIGNED -eq 1 ]] || die "BECKON_NOTARY_PROFILE is set but BECKON_SIGN_IDENTITY is not." \
      "Apple only notarizes Developer-ID-signed code; an ad-hoc signed app would be rejected." \
      "Either set BECKON_SIGN_IDENTITY too, or unset BECKON_NOTARY_PROFILE for a local/unsigned build."
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  [[ -n "$NOTARY_KEYCHAIN" ]] && NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
  SUBMIT_ZIP="$STAGE/Beckon-notarize.zip"
  rm -f "$SUBMIT_ZIP"
  ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
  notarize "$SUBMIT_ZIP" "Beckon.app"
  info "stapling Beckon.app"
  xcrun stapler staple -q "$APP"
  xcrun stapler validate -q "$APP" || die "stapler validate failed for the app."
  NOTARIZED=1
else
  if [[ $SIGNED -eq 1 ]]; then
    warn "BECKON_NOTARY_PROFILE is not set: the app is signed but NOT notarized. macOS will refuse to open it"
    warn "on other Macs. Create a profile once with 'xcrun notarytool store-credentials <name> ...' and export"
    warn "BECKON_NOTARY_PROFILE=<name> (details in DISTRIBUTION.md)."
  else
    info "skipped (unsigned build)"
  fi
fi

# ---------- 4. zip ---------------------------------------------------------------------------------
step "Zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
info "$ZIP"

# ---------- 5. dmg ---------------------------------------------------------------------------------
step "DMG"
DMG_ROOT="$STAGE/dmgroot"
rm -rf "$DMG_ROOT"; mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/Beckon.app"
ln -s /Applications "$DMG_ROOT/Applications"
# Detach any stale mount of a previous run with the same volume name (keeps the script re-runnable).
for v in /Volumes/"$VOLNAME"*; do [[ -d "$v" ]] && hdiutil detach "$v" -quiet -force 2>/dev/null || true; done
rm -f "$DMG"
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" \
  || die "hdiutil create failed."
info "$DMG"

if [[ $NOTARIZED -eq 1 ]]; then
  notarize "$DMG" "Beckon-$VERSION.dmg"
  info "stapling dmg"
  xcrun stapler staple -q "$DMG"
  xcrun stapler validate -q "$DMG" || die "stapler validate failed for the dmg."
fi

# ---------- 6. verify what a user's Mac will see -----------------------------------------------------
step "Gatekeeper assessment"
if [[ $NOTARIZED -eq 1 ]]; then
  spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/    /' || die "spctl rejected the app even though it was notarized."
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | sed 's/^/    /' || warn "spctl did not accept the dmg (the app inside is still fine)."
else
  info "skipped: $( [[ $SIGNED -eq 1 ]] && echo 'signed but not notarized' || echo 'unsigned build' ) would be rejected by Gatekeeper on other Macs"
fi

# ---------- 7. appcast.json ------------------------------------------------------------------------
step "Appcast"
if [[ -f "$NOTES_FILE" ]]; then NOTES="$(cat "$NOTES_FILE")"; info "notes from release/NOTES.md"
else NOTES="Beckon $VERSION"; warn "release/NOTES.md not found; using a one-line note."; fi
PUBLISHED="$(date -u +%Y-%m-%d)"
DMG_URL="$DOWNLOAD_BASE/Beckon-$VERSION.dmg"
{
  printf '{\n'
  printf '  "version": "%s",\n'   "$(printf '%s' "$VERSION"   | json_escape)"
  printf '  "url": "%s",\n'       "$(printf '%s' "$DMG_URL"   | json_escape)"
  printf '  "notes": "%s",\n'     "$(printf '%s' "$NOTES"     | json_escape)"
  printf '  "published": "%s"\n'  "$PUBLISHED"
  printf '}\n'
} > "$APPCAST"
if command -v jq >/dev/null 2>&1; then jq -e . "$APPCAST" >/dev/null || die "Generated appcast.json is not valid JSON."; fi
info "$APPCAST  ->  $DMG_URL"
[[ -n "$FEED_URL" ]] && info "app reads its feed from: $FEED_URL (BeckonUpdateFeedURL)" \
                     || info "Info.plist has no BeckonUpdateFeedURL yet; publish appcast.json at https://beckon.shubham.club/appcast.json"
# Cloudflare Pages / Netlify style redirect so the site can link to a stable "latest" path.
printf '/latest/Beckon.dmg  /releases/Beckon-%s.dmg  302\n/latest/Beckon.zip  /releases/Beckon-%s.zip  302\n' "$VERSION" "$VERSION" > "$DIST/_redirects"
info "$DIST/_redirects  (/latest/Beckon.dmg -> /releases/Beckon-$VERSION.dmg)"

# ---------- 8. checksums ---------------------------------------------------------------------------
step "SHA-256"
(cd "$DIST" && shasum -a 256 "Beckon-$VERSION.dmg" "Beckon-$VERSION.zip" appcast.json) | tee "$SUMS" | sed 's/^/    /'

rm -rf "$STAGE"

# ---------- summary --------------------------------------------------------------------------------
printf '\n%s%sDone.%s  dist/\n' "$BOLD" "$GRN" "$RST"
(cd "$DIST" && ls -la "Beckon-$VERSION.dmg" "Beckon-$VERSION.zip" appcast.json _redirects SHA256SUMS.txt | awk '{printf "    %8s  %s\n", $5, $9}')
if [[ $NOTARIZED -eq 1 ]]; then
  printf '    signed with Developer ID, notarized and stapled: ready to publish.\n'
elif [[ $SIGNED -eq 1 ]]; then
  printf '%s    signed but NOT notarized: users will see "Apple could not verify" until you notarize.%s\n' "$YEL" "$RST"
else
  printf '%s    UNSIGNED (ad-hoc) build: for local testing only. Do not publish this to the download page.%s\n' "$YEL" "$RST"
fi
printf '    next: copy dist/Beckon-%s.dmg to site/releases/, dist/appcast.json and dist/_redirects to site/, then deploy (site/README.md).\n' "$VERSION"
