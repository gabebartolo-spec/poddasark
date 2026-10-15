#!/usr/bin/env bash
# Runs the project's pinned Godot version (Linux), downloading it on first use.
# Usage: tools/godot.sh [godot args...]
#   tools/godot.sh --headless --path . -s tests/run_tests.gd
# On your own PC, just use your installed Godot 4.7.2 editor instead.
set -euo pipefail
VERSION="4.7.2-stable"
CACHE="${GODOT_CACHE:-$HOME/.cache/poddasark-godot}"
BIN="$CACHE/Godot_v${VERSION}_linux.x86_64"
if [ ! -x "$BIN" ]; then
  mkdir -p "$CACHE"
  curl -sSL -o "$CACHE/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${VERSION}/Godot_v${VERSION}_linux.x86_64.zip"
  unzip -oq "$CACHE/godot.zip" -d "$CACHE"
  rm "$CACHE/godot.zip"
fi
exec "$BIN" "$@"
