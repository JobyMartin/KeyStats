#!/bin/bash
set -euo pipefail

# Builds and installs /Applications/KeyStatsApp.app from this source tree.
# Idempotent — safe to re-run any time you want to update the installed app.
#
#   ./build-app.sh                build + install (quits and relaunches the app)
#   ./build-app.sh --no-install   build into ./build only, don't touch /Applications
#
# After ANY rebuild, macOS will very likely require Accessibility permission
# to be re-granted — see the message printed at the end. This is expected,
# not a bug: the ad-hoc signature (and its hash) changes on every build.

REPO="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ID="com.joby.KeyStatsApp"
APP_NAME="KeyStatsApp"
SIGN_IDENTITY="KeyStats Local Signing"
PRODUCT="KeyStats"          # SwiftPM executable target/product name
DEPLOY_TARGET="14.0"
ARCH="arm64"                # this Mac is arm64 and has no Xcode; see README
SCRATCH="$REPO/.build-$ARCH"
STAGE="$REPO/build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
DB_DIR="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/KeyStats"
DB="$DB_DIR/keystats.sqlite"
BACKUP_DIR="$HOME/KeyStats-backups"

INSTALL=1
for a in "$@"; do
  case "$a" in
    --no-install) INSTALL=0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

# ---- 1. build ----------------------------------------------------------
# NOTE: `swift build --arch` does not exist in this toolchain (Swift 6.x,
# Command Line Tools only, no Xcode). Build with --triple instead.
TRIPLE="${ARCH}-apple-macosx${DEPLOY_TARGET}"
echo "==> swift build --triple $TRIPLE"
swift build -c release --triple "$TRIPLE" --scratch-path "$SCRATCH" --product "$PRODUCT"
BIN="$(swift build -c release --triple "$TRIPLE" --scratch-path "$SCRATCH" \
         --product "$PRODUCT" --show-bin-path)/$PRODUCT"
[[ -f "$BIN" ]] || { echo "expected binary missing: $BIN" >&2; exit 1; }

# ---- 2. assemble the bundle --------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$REPO/Info.plist" "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"   # 8 bytes, no trailing newline
cp "$BIN" "$STAGE/Contents/MacOS/$APP_NAME"
chmod 755 "$STAGE/Contents/MacOS/$APP_NAME"

plutil -lint "$STAGE/Contents/Info.plist"
plutil -lint "$REPO/KeyStats.entitlements"

# ---- 3. sign with a stable local identity ------------------------------
# Ad-hoc signing (--sign -) has no stable identity, so macOS keys the
# Accessibility grant to the binary's CDHash — which changes on every
# rebuild, silently losing the grant every time. Signing with a real
# (self-signed is fine) identity gives the app a stable designated
# requirement instead, so the grant survives rebuilds.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "FATAL: signing identity '$SIGN_IDENTITY' not found in your keychain." >&2
  echo "       Run ./make-signing-cert.sh once to create it, then re-run this script." >&2
  exit 1
fi

codesign --force --sign "$SIGN_IDENTITY" \
         --identifier "$BUNDLE_ID" \
         --entitlements "$REPO/KeyStats.entitlements" \
         "$STAGE"

# ---- 4. verify before touching /Applications ---------------------------
codesign --verify --deep --strict --verbose=2 "$STAGE"
ENTITLEMENTS_XML="$(codesign -d --entitlements - --xml "$STAGE" 2>/dev/null)"
grep -q 'com.apple.security.app-sandbox' <<< "$ENTITLEMENTS_XML" || {
  echo "FATAL: sandbox entitlement missing from the built bundle." >&2
  echo "       Installing this would silently switch the app to the WRONG,\
 empty database. Refusing to continue." >&2
  exit 1
}
BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE/Contents/Info.plist")"
[[ "$BUILT_ID" == "$BUNDLE_ID" ]] || {
  echo "FATAL: bundle id is '$BUILT_ID', expected '$BUNDLE_ID'." >&2
  echo "       Installing this would create a NEW, empty database container." >&2
  exit 1
}
# Captured into a variable rather than piped live into grep -q: grep -q
# exits the instant it finds a match and closes its end of the pipe, which
# can SIGPIPE-kill codesign mid-write. Under `set -o pipefail` that non-zero
# SIGPIPE exit status wins over grep's success, failing this check even when
# the signature is correct.
SIGN_INFO="$(codesign -dvvv "$STAGE" 2>&1)"
grep -q "Authority=$SIGN_IDENTITY" <<< "$SIGN_INFO" || {
  echo "FATAL: built bundle is not signed with '$SIGN_IDENTITY'." >&2
  echo "       Installing an ad-hoc-signed build would lose Accessibility" >&2
  echo "       permission on every future rebuild. Refusing to continue." >&2
  exit 1
}

[[ $INSTALL -eq 1 ]] || { echo "==> built $STAGE (not installed)"; exit 0; }

# ---- 5. quit the running app gracefully so it flushes and closes the db --
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "==> quitting running $APP_NAME (graceful, so it flushes and closes the db)"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
  for _ in $(seq 1 30); do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.5; done
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "still running after 15s; refusing to replace it. Quit it from the menu bar and re-run." >&2
    exit 1   # never SIGKILL here — that is exactly how a WAL/db gets left mid-write
  fi
fi

# ---- 6. back up the database (all three WAL-mode files) ----------------
if [[ -f "$DB" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  for f in "$DB" "$DB-wal" "$DB-shm"; do
    [[ -f "$f" ]] && cp -p "$f" "$BACKUP_DIR/$(basename "$f").$ts"
  done
  echo "==> backed up database to $BACKUP_DIR (suffix .$ts)"
fi

# ---- 7. swap the bundle --------------------------------------------------
rm -rf "$DEST.old"
[[ -d "$DEST" ]] && mv "$DEST" "$DEST.old"
ditto "$STAGE" "$DEST"
rm -rf "$DEST.old"

echo "==> installed $DEST"
echo "    CDHash: $(codesign -dvvv "$DEST" 2>&1 | awk -F= '/^CDHash/{print $2}')"
echo "    Designated requirement: $(codesign -d -r- "$DEST" 2>&1 | tail -n 1)"
echo
echo "Signed with '$SIGN_IDENTITY' — this identity is stable across rebuilds,"
echo "so Accessibility permission should now survive future updates without"
echo "being re-granted. (If this is the FIRST build since switching away from"
echo "ad-hoc signing, one final re-grant is still needed this one time.)"
echo
echo "If KeyStats ever does stop counting keystrokes after an update anyway,"
echo "the app's own dashboard/menu bar will show a warning with instructions."
echo "Manual fix, if needed:"
echo "     System Settings > Privacy & Security > Accessibility"
echo "       1. select KeyStatsApp, press '-' to remove the old entry"
echo "       2. press '+', choose /Applications/$APP_NAME.app, enable it"
echo "   (or run:  tccutil reset Accessibility $BUNDLE_ID )"
echo
open -a "$DEST"
echo "==> launched. Watch the log with:"
echo "    log stream --predicate 'process == \"$APP_NAME\"' --info"
