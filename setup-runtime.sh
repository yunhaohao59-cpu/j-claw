#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/runtime"
NODE_VERSION="v24.15.0"
OPENCLAW_VERSION="latest"

PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$PLATFORM" in
    linux)
        case "$ARCH" in
            x86_64)  NODE_DIST="linux-x64" ;;
            aarch64) NODE_DIST="linux-arm64" ;;
            armv7l)  NODE_DIST="linux-armv7l" ;;
            *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
        esac
        NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${NODE_DIST}.tar.xz"
        ;;
    darwin)
        case "$ARCH" in
            x86_64)  NODE_DIST="darwin-x64" ;;
            arm64)   NODE_DIST="darwin-arm64" ;;
            *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
        esac
        NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${NODE_DIST}.tar.gz"
        ;;
    mingw*|msys*|cygwin*)
        case "$ARCH" in
            x86_64)  NODE_DIST="win-x64" ;;
            *)       echo "Unsupported arch: $ARCH"; exit 1 ;;
        esac
        NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${NODE_DIST}.zip"
        ;;
    *)
        echo "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

echo "=== J-Claw Runtime Setup ==="
echo "Platform: $PLATFORM/$ARCH"
echo "Node dist: $NODE_DIST"
echo "Runtime dir: $RUNTIME_DIR"
echo ""

mkdir -p "$RUNTIME_DIR"

# ── Node.js ──
NODE_DIR="$RUNTIME_DIR/node"
if [ -x "$NODE_DIR/bin/node" ]; then
    echo "[skip] Node.js already installed at $NODE_DIR"
else
    echo "--- Downloading Node.js ${NODE_VERSION} ---"
    rm -rf "$NODE_DIR"
    mkdir -p "$NODE_DIR"

    ARCHIVE="$RUNTIME_DIR/node-archive"

    if command -v curl &>/dev/null; then
        curl -fSL --progress-bar "$NODE_URL" -o "$ARCHIVE"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress "$NODE_URL" -O "$ARCHIVE"
    else
        echo "ERROR: need curl or wget"; exit 1
    fi

    echo "Extracting..."
    if [[ "$ARCHIVE" == *.tar.xz ]]; then
        tar -xJf "$ARCHIVE" -C "$RUNTIME_DIR"
    elif [[ "$ARCHIVE" == *.tar.gz ]]; then
        tar -xzf "$ARCHIVE" -C "$RUNTIME_DIR"
    elif [[ "$ARCHIVE" == *.zip ]]; then
        unzip -q "$ARCHIVE" -d "$RUNTIME_DIR"
    fi

    rm -f "$ARCHIVE"

    # Find the extracted directory and rename to node
    EXTRACTED_DIR=$(ls -d "$RUNTIME_DIR"/node-${NODE_VERSION}-* 2>/dev/null | head -1)
    if [ -d "$EXTRACTED_DIR" ]; then
        rm -rf "$NODE_DIR"
        mv "$EXTRACTED_DIR" "$NODE_DIR"
    fi

    if [ ! -x "$NODE_DIR/bin/node" ]; then
        echo "ERROR: Node.js binary not found after extraction"
        exit 1
    fi
    echo "[ok] Node.js installed: $("$NODE_DIR/bin/node" --version)"
fi

export PATH="$NODE_DIR/bin:$PATH"

# ── openclaw ──
OC_DIR="$RUNTIME_DIR/openclaw"
if [ -f "$OC_DIR/openclaw.mjs" ]; then
    echo "[skip] openclaw already installed at $OC_DIR"
else
    echo "--- Installing openclaw@${OPENCLAW_VERSION} ---"
    mkdir -p "$OC_DIR"

    cd "$OC_DIR"
    npm init -y --silent 2>/dev/null || true
    npm install "openclaw@${OPENCLAW_VERSION}" --omit=dev --no-audit --no-fund 2>&1 | tail -3

    # Copy from node_modules to flat structure
    INSTALLED=$(ls -d node_modules/openclaw 2>/dev/null | head -1)
    if [ -n "$INSTALLED" ]; then
        cp -a "$INSTALLED"/. . 2>/dev/null || true
        # Keep the full node_modules (openclaw needs its own deps too)
        echo "[ok] openclaw installed: $(node openclaw.mjs --version 2>/dev/null || echo 'unknown')"
    else
        echo "ERROR: openclaw installation failed"
        exit 1
    fi
fi

# ── Config dir ──
CONFIG_DIR="$SCRIPT_DIR/config"
mkdir -p "$CONFIG_DIR"
echo "[ok] Config dir: $CONFIG_DIR"

echo ""
echo "=== Setup complete ==="
echo "Node: $("$NODE_DIR/bin/node" --version)"
echo "openclaw: $(cd "$OC_DIR" && node openclaw.mjs --version 2>/dev/null || echo 'ready')"
echo "Runtime: $RUNTIME_DIR"
echo ""
echo "Next: ./build.sh build && ./build.sh gui"
