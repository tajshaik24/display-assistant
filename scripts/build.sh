#!/bin/zsh
# Builds Display Assistant and, with --install, copies it to /Applications and relaunches it.
set -euo pipefail

cd "$(dirname "$0")/.."
# xcode-select may point at the Command Line Tools; use the full Xcode for this build only.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcodegen generate --quiet
xcodebuild -project DisplayAssistant.xcodeproj -scheme DisplayAssistant -configuration Release \
    -derivedDataPath build -quiet build

app="build/Build/Products/Release/Display Assistant.app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "Display Assistant" || true
    rm -rf "/Applications/Display Assistant.app"
    cp -R "$app" /Applications/
    open "/Applications/Display Assistant.app"
    echo "Installed and launched /Applications/Display Assistant.app"
fi
