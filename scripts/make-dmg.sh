#!/bin/bash
set -euo pipefail

# Wrap a signed, notarized "Display Assistant.app" in a disk image for the website download:
# the app beside an Applications shortcut, so installing is a single drag.
# Usage: scripts/make-dmg.sh APP_BUNDLE OUTPUT_DMG [--notarize] [--keychain-profile NAME]
#
# With --notarize the image is signed with Developer ID, notarized and stapled, so it opens without
# Gatekeeper warnings even offline. Credentials as in build-app.sh: ~/.appstoreconnect/config.json,
# or --keychain-profile NAME.

APP_BUNDLE="${1:?usage: make-dmg.sh APP_BUNDLE OUTPUT_DMG [--notarize] [--keychain-profile NAME]}"
OUTPUT_DMG="${2:?usage: make-dmg.sh APP_BUNDLE OUTPUT_DMG [--notarize] [--keychain-profile NAME]}"
shift 2
NOTARIZE=false
KEYCHAIN_PROFILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --notarize) NOTARIZE=true; shift ;;
        --keychain-profile) KEYCHAIN_PROFILE="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP_BUNDLE" "$STAGING/$(basename "$APP_BUNDLE")"
ln -s /Applications "$STAGING/Applications"

echo "Creating disk image..."
rm -f "$OUTPUT_DMG"
hdiutil create -quiet -volname "Display Assistant" -srcfolder "$STAGING" -fs APFS -format ULFO "$OUTPUT_DMG"

if [[ "$NOTARIZE" == true ]]; then
    codesign --sign "Developer ID Application" --timestamp "$OUTPUT_DMG"

    if [[ -n "$KEYCHAIN_PROFILE" ]]; then
        NOTARY_AUTH=(--keychain-profile "$KEYCHAIN_PROFILE")
    else
        ASC_CONFIG="$HOME/.appstoreconnect/config.json"
        ASC_KEY_ID=$(plutil -extract keyID raw "$ASC_CONFIG")
        ASC_ISSUER=$(plutil -extract issuerID raw "$ASC_CONFIG")
        NOTARY_AUTH=(--key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER")
    fi

    echo "Submitting disk image to Apple notary service..."
    # notarytool exits 0 even when Apple rejects the submission, so check the status it reports.
    NOTARY_OUTPUT=$(xcrun notarytool submit "$OUTPUT_DMG" "${NOTARY_AUTH[@]}" --wait 2>&1 | tee /dev/stderr)
    if ! grep -q "status: Accepted" <<< "$NOTARY_OUTPUT"; then
        SUBMISSION_ID=$(grep -m1 -E "^ *id: " <<< "$NOTARY_OUTPUT" | awk '{print $2}')
        echo "Error: notarization was not accepted. See why with:"
        echo "  xcrun notarytool log $SUBMISSION_ID ${NOTARY_AUTH[*]}"
        exit 1
    fi
    xcrun stapler staple "$OUTPUT_DMG"
    xcrun stapler validate "$OUTPUT_DMG"
fi

echo "Disk image: $OUTPUT_DMG"
