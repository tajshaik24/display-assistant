#!/bin/bash
set -euo pipefail

# Build "Display Assistant.app" (the app plus its Control Center extension).
# Usage: ./build-app.sh [release|debug] [--identity IDENTITY] [--install] [--notarize] [--keychain-profile NAME]
#
# Code signing: Auto-detects an "Apple Development" identity for stable TCC permissions.
# Use --identity to override (e.g. --identity "-" for ad-hoc, or a specific identity name).
# Use --install to copy the built app to /Applications/ and relaunch it.
#
# Notarization (--notarize): signs with a "Developer ID Application" certificate
# (requires a paid Apple Developer Program membership), submits the app to Apple's
# notary service, then staples the ticket so it opens without Gatekeeper warnings.
# Credentials are read from a notarytool keychain profile (default: "DisplayAssistantNotary").
# Create it once with:
#   xcrun notarytool store-credentials "DisplayAssistantNotary" \
#     --apple-id tajshaik24@gmail.com --team-id LDUCPMFSMH --password <app-specific-password>
# Override the profile name with --keychain-profile NAME.
#
# Requires Xcode and XcodeGen (brew install xcodegen). The app has an app extension,
# so it is built with xcodebuild rather than Swift Package Manager alone.

BUILD_CONFIG="${1:-release}"
SIGN_IDENTITY=""
INSTALL=false
NOTARIZE=false
KEYCHAIN_PROFILE="DisplayAssistantNotary"

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
# Extra xcodebuild settings; empty means "use what project.yml says" (Apple Development, team LDUCPMFSMH).
SIGN_SETTINGS=()
if [[ -z "$SIGN_IDENTITY" ]]; then
    if [[ "$NOTARIZE" == true ]]; then
        # `|| true` so set -e doesn't abort before the friendly error below when grep finds nothing
        DETECTED=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk '{print $2}' || true)
        if [[ -z "$DETECTED" ]]; then
            echo "Error: --notarize requires a 'Developer ID Application' certificate, but none was found."
            echo "       That certificate is only issued to paid Apple Developer Program members."
            echo "       Create one in Xcode > Settings > Accounts (or developer.apple.com), then re-run."
            exit 1
        fi
        SIGN_IDENTITY="Developer ID Application"
        echo "Using Developer ID signing identity: $DETECTED"
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
    # The notary service rejects signatures without a secure timestamp.
    SIGN_SETTINGS+=(OTHER_CODE_SIGN_FLAGS=--timestamp)
fi

# A unique, increasing build number for every build. The system caches the extension's
# Control Center controls per version, so without this, added or changed controls never show up.
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

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
codesign --verify --deep --strict "$APP_BUNDLE"

echo ""
echo "Done! App bundle created at:"
echo "  $APP_BUNDLE"
echo ""

# --- Notarize ---
# Runs before --install so the installed copy is stapled.
if [[ "$NOTARIZE" == true ]]; then
    NOTARY_ZIP="$OUTPUT_DIR/DisplayAssistant.zip"

    echo "Zipping app for notarization..."
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

    echo "Submitting to Apple notary service (profile: $KEYCHAIN_PROFILE)..."
    xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

    echo "Stapling ticket to app bundle..."
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"

    echo "Re-zipping stapled app for distribution..."
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

    echo ""
    echo "Notarized & stapled. Upload this to the GitHub release:"
    echo "  $NOTARY_ZIP"
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
