#!/usr/bin/env bash
# Sign and notarize an already-built app using the owner's local runbook.
# No certificate, password, API key, or credential content is copied into this project.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_INPUT="${1:-$PROJECT_ROOT/build/Wake Up Sunshine.app}"
[ -d "$APP_INPUT/Contents" ] || { echo "Build the app first: scripts/build.sh" >&2; exit 2; }
APP_PATH="$(cd "$(dirname "$APP_INPUT")" && pwd)/$(basename "$APP_INPUT")"
OUTPUT_DIR="$(dirname "$APP_PATH")"
ENTITLEMENTS="${2:-$PROJECT_ROOT/Resources/WakeUpSunshine.entitlements}"
CRED_ROOT="${CRED_ROOT:-/Users/ccarpio/Library/CloudStorage/OneDrive-Personal/A07-Desarrollador}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY_PROFILE}"
LOG_DIR="$OUTPUT_DIR/release-logs"
mkdir -p "$LOG_DIR"
trap 'echo "Release stopped at line $LINENO. See build/release-logs for command output." >&2' ERR

run_step() {
  local label="$1"
  shift
  echo "→ $label"
  if "$@" > "$LOG_DIR/$label.log" 2>&1; then
    cat "$LOG_DIR/$label.log"
  else
    local result=$?
    echo "Failed: $label ($result)" >&2
    tail -50 "$LOG_DIR/$label.log" >&2
    exit "$result"
  fi
}

run_step check-xcode xcode-select -p
run_step check-codesign xcrun --find codesign
run_step check-notarytool xcrun --find notarytool
run_step check-stapler xcrun --find stapler
# Use the certificate SHA-1 so accented identity names survive any shell locale.
source "$PROJECT_ROOT/scripts/lib/developer-id.sh"
# Keep the existing explicit override, but require a complete fingerprint rather than a name.
if [[ -n "${SIGNING_IDENTITY:-}" && -z "${DEVELOPER_ID_SHA1+x}" ]]; then
  DEVELOPER_ID_SHA1="$SIGNING_IDENTITY"
fi
select_developer_id || exit 2
SIGNING_IDENTITY="$DEVELOPER_ID_HASH"
# Read identifiers at runtime so rotating them requires no source change.
KEY_ID="$(tr -d '[:space:]' < "$CRED_ROOT/App Store Connect API/Key ID.txt")"
ISSUER_ID="$(tr -d '[:space:]' < "$CRED_ROOT/App Store Connect API/Issuer ID.txt")"
P8_PATH="$CRED_ROOT/App Store Connect API/AuthKey_${KEY_ID}.p8"
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > "$LOG_DIR/profile-check.log" 2>&1; then
  echo "Using existing notarization profile."
elif /usr/bin/grep -Eqi 'could not find|no keychain password item|does not exist|profile.*not found' "$LOG_DIR/profile-check.log"; then
  # Suppress successful credential setup output; never echo credentials.
  if ! xcrun notarytool store-credentials "$NOTARY_PROFILE" --key "$P8_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" > /dev/null 2>&1; then
    echo "Failed: notarytool store-credentials. Verify the original API credential files and keychain access." >&2
    exit 2
  fi
else
  echo "Failed: notarytool history. Profile verification failed; credentials were not replaced." >&2
  tail -50 "$LOG_DIR/profile-check.log" >&2
  exit 2
fi
unset KEY_ID ISSUER_ID P8_PATH

# This app has one Mach-O and no nested frameworks. Sign inside-out.
run_step sign-executable codesign --force --timestamp --options=runtime --sign "$SIGNING_IDENTITY" "$APP_PATH/Contents/MacOS/WakeUpSunshine"
run_step sign-bundle codesign --force --timestamp --options=runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" "$APP_PATH"
run_step verify-signature codesign --verify --deep --strict --verbose=2 "$APP_PATH"
verify_developer_id_signature "$APP_PATH"
run_step show-signature codesign --display --verbose=4 "$APP_PATH"
SUBMISSION_ZIP="$OUTPUT_DIR/WakeUpSunshine-submission.zip"
run_step prepare-submission /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
SUBMIT_JSON="$OUTPUT_DIR/notarization.json"
echo "Submitting to Apple; waiting for notarization…"
SUBMIT_RESULT=0
xcrun notarytool submit "$SUBMISSION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m --output-format json > "$SUBMIT_JSON" 2> "$LOG_DIR/notary-submit.log" || SUBMIT_RESULT=$?
SUBMISSION_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$SUBMIT_JSON" 2>/dev/null || true)"
STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$SUBMIT_JSON" 2>/dev/null || true)"
if [ "$SUBMIT_RESULT" -ne 0 ] || [ "$STATUS" != Accepted ]; then
  echo "Failed: notarytool submit (exit=$SUBMIT_RESULT, status=${STATUS:-unknown})." >&2
  tail -50 "$LOG_DIR/notary-submit.log" >&2
  if [ -n "$SUBMISSION_ID" ]; then
    # Fetch diagnostics on every failed submission with an available ID.
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" "$OUTPUT_DIR/notarization-log.json" || true
    [ ! -f "$OUTPUT_DIR/notarization-log.json" ] || tail -50 "$OUTPUT_DIR/notarization-log.json" >&2
  fi
  exit 1
fi
run_step staple-ticket xcrun stapler staple "$APP_PATH"
run_step validate-ticket xcrun stapler validate "$APP_PATH"
run_step assess-gatekeeper spctl --assess --type execute --verbose=4 "$APP_PATH"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ZIP_NAME="WakeUpSunshine-$VERSION-macOS.zip"
# Archive AFTER stapling so the downloadable copy contains the offline ticket.
run_step package-download /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$OUTPUT_DIR/$ZIP_NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
echo "Signed, notarized, stapled, and verified: $OUTPUT_DIR/$ZIP_NAME"
