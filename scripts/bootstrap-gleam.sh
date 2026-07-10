#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
GLEAM_VERSION="1.16.0"
GLEAM_DIR="$PROJECT_ROOT/.automation-local"
GLEAM_BIN="$GLEAM_DIR/gleam"

mkdir -p "$GLEAM_DIR"

if [ -f "$GLEAM_BIN" ]; then
    echo "Gleam already installed at $GLEAM_BIN"
    exit 0
fi

echo "Bootstrapping Gleam $GLEAM_VERSION..."

case "$(uname -s)" in
    Darwin*)
        if [ "$(uname -m)" = "arm64" ]; then
            GLEAM_URL="https://github.com/gleam-lang/gleam/releases/download/v$GLEAM_VERSION/gleam-v$GLEAM_VERSION-aarch64-apple-darwin.tar.gz"
        else
            GLEAM_URL="https://github.com/gleam-lang/gleam/releases/download/v$GLEAM_VERSION/gleam-v$GLEAM_VERSION-x86_64-apple-darwin.tar.gz"
        fi
        ;;
    Linux*)
        GLEAM_URL="https://github.com/gleam-lang/gleam/releases/download/v$GLEAM_VERSION/gleam-v$GLEAM_VERSION-x86_64-unknown-linux-musl.tar.gz"
        ;;
    *)
        echo "Unsupported platform: $(uname -s)"
        exit 1
        ;;
esac

echo "Downloading from $GLEAM_URL..."
curl -L "$GLEAM_URL" | tar xz -C "$GLEAM_DIR"

chmod +x "$GLEAM_BIN"

echo "Gleam installed successfully at $GLEAM_BIN"
echo "Add to PATH: export PATH=\"$GLEAM_DIR:\$PATH\""
