#!/usr/bin/env bash
set -euo pipefail

# Scripts/build-app.sh
# Builds the Swift executable and packages it into a native macOS .app bundle

APP_NAME="AntigravityCodex"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Building Swift release executable..."
swift build -c release

RELEASE_BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "==> Packaging into ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

cp "${RELEASE_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Generate Info.plist
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AntigravityCodex</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.codex</string>
    <key>CFBundleName</key>
    <string>AntigravityCodex</string>
    <key>CFBundleDisplayName</key>
    <string>Antigravity</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

# Stage bundled binary
if [ -f "./Scripts/bundle-acp.sh" ]; then
    bash ./Scripts/bundle-acp.sh "${APP_BUNDLE}" || true
fi

# Ad-hoc sign bundle
echo "==> Ad-hoc signing ${APP_BUNDLE}..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Successfully created ${APP_BUNDLE}!"
echo "You can now run: open ./${APP_BUNDLE}"
