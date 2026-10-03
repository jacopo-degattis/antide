#!/usr/bin/env bash
set -euo pipefail

# Scripts/bundle-acp.sh
# Bundles the refined-antigravity-acp dependencies and launcher into an .app bundle or local distribution

APP_DIR="${1:-./AntigravityCodex.app}"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
BIN_DIR="$RESOURCES_DIR/bin"

echo "==> Preparing target directory: $BIN_DIR"
mkdir -p "$BIN_DIR"

# 1. Check if Node is installed
NODE_PATH=$(which node || true)
if [ -z "$NODE_PATH" ]; then
    echo "Warning: Node.js was not found in PATH. Subprocess will rely on system path discovery."
else
    echo "==> Detected Node.js at $NODE_PATH"
fi

# 2. Install / prepare @simonepri/refined-antigravity-acp
echo "==> Staging @simonepri/refined-antigravity-acp into $BIN_DIR"
mkdir -p "$BIN_DIR/node_modules"

if command -v pnpm &>/dev/null; then
    (cd "$BIN_DIR" && pnpm add @simonepri/refined-antigravity-acp)
elif command -v npm &>/dev/null; then
    (cd "$BIN_DIR" && npm install --no-audit --no-fund @simonepri/refined-antigravity-acp)
fi

# 3. Create standalone launcher wrapper
cat << 'EOF' > "$BIN_DIR/refined-antigravity-acp"
#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NODE_EXEC=$(which node || echo "/usr/local/bin/node")

if [ -f "$DIR/node_modules/.bin/refined-antigravity-acp" ]; then
    exec "$DIR/node_modules/.bin/refined-antigravity-acp" "$@"
else
    exec "$NODE_EXEC" "$DIR/node_modules/@simonepri/refined-antigravity-acp/bin/index.js" "$@"
fi
EOF

chmod +x "$BIN_DIR/refined-antigravity-acp"

echo "==> Standalone bundle successfully staged at $BIN_DIR/refined-antigravity-acp"
