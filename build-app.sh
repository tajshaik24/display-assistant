#!/bin/bash
set -euo pipefail

# Build "Display Assistant.app" (the app plus its Control Center extension).
# Usage: ./build-app.sh [release|debug] [--identity IDENTITY] [--install] [--notarize] [--notes FILE] [--keychain-profile NAME]
#
# Code signing: Auto-detects a "Developer ID Application" identity (what releases use), falling back to
# "Apple Development", so the Accessibility permission survives rebuilds and Sparkle updates.
# Use --identity to override (e.g. --identity "-" for ad-hoc, or a specific identity name).
# Use --install to copy the built app to /Applications/ and relaunch it.
#
# Notarization (--notarize): signs with a "Developer ID Application" certificate
# (requires a paid Apple Developer Program membership), submits the app to Apple's
# notary service, then staples the ticket so it opens without Gatekeeper warnings.
# Credentials: an App Store Connect API key described by ~/.appstoreconnect/config.json
# (keyID, issuerID, and the key at ~/.appstoreconnect/private_keys/AuthKey_<keyID>.p8).
# Alternatively pass --keychain-profile NAME to use a profile made with `xcrun notarytool store-credentials`.
#
# Updates (Sparkle): a notarized build also writes build/appcast.xml, with the zip signed by the
# Sparkle EdDSA key in the login keychain (account "display-assistant"; public key in project.yml).
# --notes FILE puts that Markdown file in the appcast as the release notes Sparkle shows.
# Attach both build/DisplayAssistant-<version>.zip and build/appcast.xml to the GitHub release;
# the app reads the appcast from the latest release.
#
# Requires Xcode and XcodeGen (brew install xcodegen). The app has an app extension,
# so it is built with xcodebuild rather than Swift Package Manager alone.

BUILD_CONFIG="${1:-release}"
SIGN_IDENTITY=""
INSTALL=false
NOTARIZE=false
KEYCHAIN_PROFILE=""
NOTES_FILE=""

# Parse optional flags
[[ $# -gt 0 && "$1" != --* ]] && shift
[[ "$BUILD_CONFIG" == --* ]] && BUILD_CONFIG="release"
while [[ $# -gt 0 ]]; do
    case $1 in
        --identity)
            SIGN_IDENTITY="${2:-}"
            shift 2
            ;;
        --install)
            INSTALL=true
            shift
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --notes)
            NOTES_FILE="${2:-}"
            shift 2
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

APP_NAME="Display Assistant"
SCHEME="DisplayAssistant"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/build"
cd "$SCRIPT_DIR"

# --- Tooling ---
# xcode-select may point at the Command Line Tools; use the full Xcode for this build only.
if ! xcodebuild -version > /dev/null 2>&1; then
    if [[ -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
        echo "Error: Xcode is required (the Command Line Tools alone can't build the app extension)."
        exit 1
    fi
fi
if ! command -v xcodegen > /dev/null 2>&1; then
    echo "Error: XcodeGen is required. Install it with: brew install xcodegen"
    exit 1
fi

# --- Signing identity ---
# Extra xcodebuild settings; empty means "use what project.yml says" (Apple Development).
SIGN_SETTINGS=()
if [[ -z "$SIGN_IDENTITY" ]]; then
    # Prefer Developer ID, the identity releases use: macOS ties the Accessibility permission to the
    # signature, so a local build signed differently from the updates Sparkle installs would make it
    # ask for Accessibility again every time one replaced the other.
    # `|| true` so set -e doesn't abort when grep finds nothing.
    DETECTED=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk '{print $2}' || true)
    if [[ -n "$DETECTED" ]]; then
        SIGN_IDENTITY="Developer ID Application"
        echo "Using Developer ID signing identity: $DETECTED"
    elif [[ "$NOTARIZE" == true ]]; then
        echo "Error: --notarize requires a 'Developer ID Application' certificate, but none was found."
        echo "       Only the Account Holder can create it: Xcode > Settings > Accounts > Manage Certificates."
        exit 1
    else
        DETECTED=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}' || true)
        if [[ -n "$DETECTED" ]]; then
            echo "Using signing identity: $DETECTED"
        else
            SIGN_IDENTITY="-"
            echo "Warning: No Apple Development identity found. Using ad-hoc signing (-)."
            echo "         The Accessibility permission will reset on each rebuild."
            echo "         Add a development certificate in Xcode for persistent permissions."
        fi
    fi
fi
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_SETTINGS=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
elif [[ -n "$SIGN_IDENTITY" ]]; then
    SIGN_SETTINGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY")
fi
if [[ "$NOTARIZE" == true ]]; then
    # The notary service rejects signatures without a secure timestamp, and executables that allow
    # debugging (Xcode adds the get-task-allow entitlement unless told not to).
    SIGN_SETTINGS+=(OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi

# A unique, increasing build number for every build. The system caches the extension's
# Control Center controls per version, so without this, added or changed controls never show up.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

# --- Build ---
if [[ "$BUILD_CONFIG" == "debug" ]]; then CONFIGURATION="Debug"; else CONFIGURATION="Release"; fi
echo "Building $APP_NAME ($CONFIGURATION)..."
xcodegen generate --quiet
# Even with -quiet, xcodebuild prints two harmless lines on every build; drop them.
xcodebuild -project DisplayAssistant.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination "platform=macOS,arch=arm64" -derivedDataPath "$OUTPUT_DIR" -quiet build CURRENT_PROJECT_VERSION="$BUILD_NUMBER" ${SIGN_SETTINGS[@]+"${SIGN_SETTINGS[@]}"} \
    2> >(grep -Ev "exit code 0 but produced no further output|IDERunDestination: Supported platforms" >&2)

APP_BUNDLE="$OUTPUT_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Error: could not find built app at $APP_BUNDLE"
    exit 1
fi
if [[ "$SIGN_IDENTITY" == "Developer ID Application" ]]; then
    # Xcode signs Sparkle.framework but not the helpers inside it, which keep Sparkle's ad-hoc
    # signatures; notarization needs every executable signed with Developer ID and a timestamp,
    # and local builds get the same treatment so they match releases exactly.
    # Inside out, as Sparkle's documentation describes, then the app again to seal the new framework.
    SPARKLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    SIGN=(codesign --force --sign "Developer ID Application" --options runtime --timestamp)
    "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
    "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
    "${SIGN[@]}" "$SPARKLE"
    "${SIGN[@]}" --preserve-metadata=entitlements "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

echo ""
echo "Done! App bundle created at:"
echo "  $APP_BUNDLE"
echo ""

# --- Notarize ---
# Runs before --install so the installed copy is stapled.
if [[ "$NOTARIZE" == true ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
    NOTARY_ZIP="$OUTPUT_DIR/DisplayAssistant-$VERSION.zip"
    if [[ -n "$KEYCHAIN_PROFILE" ]]; then
        NOTARY_AUTH=(--keychain-profile "$KEYCHAIN_PROFILE")
    else
        ASC_CONFIG="$HOME/.appstoreconnect/config.json"
        if [[ ! -f "$ASC_CONFIG" ]]; then
            echo "Error: no notary credentials. Create $ASC_CONFIG or pass --keychain-profile NAME."
            exit 1
        fi
        ASC_KEY_ID=$(plutil -extract keyID raw "$ASC_CONFIG")
        ASC_ISSUER=$(plutil -extract issuerID raw "$ASC_CONFIG")
        NOTARY_AUTH=(--key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER")
    fi

    echo "Zipping app for notarization..."
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

    echo "Submitting to Apple notary service..."
    # notarytool exits 0 even when Apple rejects the app, so check the status it reports.
    NOTARY_OUTPUT=$(xcrun notarytool submit "$NOTARY_ZIP" "${NOTARY_AUTH[@]}" --wait 2>&1 | tee /dev/stderr)
    if ! grep -q "status: Accepted" <<< "$NOTARY_OUTPUT"; then
        SUBMISSION_ID=$(grep -m1 -E "^ *id: " <<< "$NOTARY_OUTPUT" | awk '{print $2}')
        echo "Error: notarization was not accepted. See why with:"
        echo "  xcrun notarytool log $SUBMISSION_ID ${NOTARY_AUTH[*]}"
        exit 1
    fi

    echo "Stapling ticket to app bundle..."
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"

    echo "Re-zipping stapled app for distribution..."
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

    # --- Appcast for Sparkle ---
    # Sparkle's sign_update tool, from the release matching the resolved package.
    SPARKLE_VERSION=$(python3 -c 'import json,sys; print(next(p["state"]["version"] for p in json.load(open(sys.argv[1]))["pins"] if p["identity"] == "sparkle"))' \
        DisplayAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)
    SPARKLE_TOOLS="$OUTPUT_DIR/sparkle-$SPARKLE_VERSION"
    if [[ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]]; then
        echo "Downloading Sparkle $SPARKLE_VERSION tools..."
        mkdir -p "$SPARKLE_TOOLS"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
            | tar -xJ -C "$SPARKLE_TOOLS" bin
    fi
    # Prints: sparkle:edSignature="..." length="..."
    SIGNATURE=$("$SPARKLE_TOOLS/bin/sign_update" --account display-assistant "$NOTARY_ZIP")
    BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_BUNDLE/Contents/Info.plist")
    MIN_SYSTEM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_BUNDLE/Contents/Info.plist")
    RELEASE_URL="https://github.com/tajshaik24/display-assistant/releases"
    NOTES=""
    if [[ -n "$NOTES_FILE" ]]; then
        NOTES=$(cat "$NOTES_FILE")
    else
        echo "Warning: no --notes FILE, so Sparkle's update window will show no release notes."
    fi
    cat > "$OUTPUT_DIR/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Display Assistant</title>
    <item>
      <title>Display Assistant $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$RELEASE_URL/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[$NOTES]]></description>
      <enclosure url="$RELEASE_URL/download/v$VERSION/DisplayAssistant-$VERSION.zip" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
APPCAST

    echo ""
    echo "Notarized & stapled. Attach both to the GitHub release v$VERSION:"
    echo "  $NOTARY_ZIP"
    echo "  $OUTPUT_DIR/appcast.xml"
    echo ""
fi

if [[ "$INSTALL" == true ]]; then
    # Quit the running instance so the new build replaces it cleanly
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        echo "Stopping running $APP_NAME..."
        osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
        sleep 1
        # Force kill if still running
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 0.5
    fi

    echo "Installing to /Applications/..."
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    # ditto keeps the bundle's old modification date, which macOS uses to decide whether its cached
    # icon is stale. Bump it and re-register so a new icon shows up in Finder and the Dock.
    touch "/Applications/$APP_NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"

    echo "Installed and launched /Applications/$APP_NAME.app"
    echo ""
    echo "First install on this Mac:"
    echo "  1. Click the display icon in the menu bar and press Enable to grant Accessibility"
    echo "     (System Settings > Privacy & Security > Accessibility) for the keyboard keys."
    echo "  2. Optional: Control Center > Edit Controls > search \"Display\"."
    echo "Launch at Login is switched on automatically."
else
    echo "To install, run:"
    echo "  ./build-app.sh $BUILD_CONFIG --install"
fi
