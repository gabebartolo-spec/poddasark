#!/usr/bin/env bash
# Exports both presets and uploads them to itch.io with butler.
# Needs two environment variables:
#   BUTLER_API_KEY  an itch.io API key (set in the environment settings, never in the repo)
#   ITCH_TARGET     "<itch username>/<game page slug>", e.g. someone/poddasark
# The itch.io page must already exist. Its visibility is set on itch.io, not here,
# so a Draft or Restricted page stays private.
set -euo pipefail
: "${BUTLER_API_KEY:?Set BUTLER_API_KEY}"
: "${ITCH_TARGET:?Set ITCH_TARGET to <username>/<game-slug>}"
cd "$(dirname "$0")/.."

BUTLER_DIR="${BUTLER_CACHE:-$HOME/.cache/poddasark-butler}"
if [ ! -x "$BUTLER_DIR/butler" ]; then
  mkdir -p "$BUTLER_DIR"
  curl -sSL -o "$BUTLER_DIR/butler.zip" https://broth.itch.zone/butler/linux-amd64/LATEST/archive/default
  unzip -oq "$BUTLER_DIR/butler.zip" -d "$BUTLER_DIR"
  rm "$BUTLER_DIR/butler.zip"
  chmod +x "$BUTLER_DIR/butler"
fi

TEMPLATES="$HOME/.local/share/godot/export_templates/4.7.2.stable"
if [ ! -f "$TEMPLATES/web_nothreads_release.zip" ]; then
  echo "Downloading Godot export templates (about 1.3 GB, first run only)..."
  TMP="$(mktemp -d)"
  curl -sSL -o "$TMP/t.tpz" \
    https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
  unzip -oq "$TMP/t.tpz" -d "$TMP"
  mkdir -p "$TEMPLATES"
  mv "$TMP"/templates/* "$TEMPLATES"/
  rm -rf "$TMP"
fi

VERSION="$(git rev-parse --short HEAD)"
rm -rf export && mkdir -p export/windows export/web
tools/godot.sh --headless --path . --import >/dev/null
tools/godot.sh --headless --path . --export-release "Windows" export/windows/poddasark.exe
tools/godot.sh --headless --path . --export-release "Web (itch.io)" export/web/index.html

"$BUTLER_DIR/butler" push export/windows "$ITCH_TARGET:windows" --userversion "$VERSION"
"$BUTLER_DIR/butler" push export/web "$ITCH_TARGET:html5" --userversion "$VERSION"
