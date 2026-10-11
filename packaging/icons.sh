#!/usr/bin/env bash
# Regenerate every app icon from assets/app-icon/photocraft.svg (the canonical master).
#
# Needs: resvg (brew install resvg / cargo install resvg). On macOS, iconutil also writes the
# .icns. The outputs are committed, so packaging never needs these tools.
#
#   packaging/icons.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/assets/app-icon"
SVG="$DIR/photocraft.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v resvg >/dev/null || { echo "error: resvg not found (brew install resvg)" >&2; exit 1; }

# The SVG is a full-bleed 512 tile (rx=112), used as-is on Windows and Linux so the rounded corners
# match the other Crafting Apps. macOS icons follow Apple's grid: the tile is 824/1024 of the canvas
# with a transparent margin, so widen the viewBox around it.
MAC="$TMP/mac.svg"
sed 's/viewBox="0 0 512 512"/viewBox="-62.136 -62.136 636.272 636.272"/' "$SVG" >"$MAC"
grep -q 'viewBox="-62.136' "$MAC" || { echo "error: $SVG has no 512 viewBox" >&2; exit 1; }

render() { resvg -w "$2" -h "$2" "$1" "$3" </dev/null; }

render "$SVG" 1024 "$DIR/photocraft-1024.png"
# Runtime window/Dock icon on macOS (embedded by apps/photocraft/src/app_icon.rs).
render "$MAC" 512 "$DIR/photocraft-macos-512.png"

# Linux hicolor theme (the 256 one is also the runtime icon on Windows and Linux).
for s in 16 24 32 48 64 128 256 512; do
  mkdir -p "$DIR/hicolor/${s}x${s}/apps"
  render "$SVG" "$s" "$DIR/hicolor/${s}x${s}/apps/ai.storyteller.photocraft.png"
done
mkdir -p "$DIR/hicolor/scalable/apps"
# The lighter trace (photocraft-small.svg) keeps the scalable theme icon cheap to render.
cp "$DIR/photocraft-small.svg" "$DIR/hicolor/scalable/apps/ai.storyteller.photocraft.svg"

# Windows .ico.
ICO_PNGS=()
for s in 16 20 24 32 40 48 64 128 256; do
  render "$SVG" "$s" "$TMP/ico-$s.png"
  ICO_PNGS+=("$TMP/ico-$s.png")
done
(cd "$ROOT" && cargo run -q -p xtask -- ico "$DIR/photocraft.ico" "${ICO_PNGS[@]}")

# macOS .icns.
if command -v iconutil >/dev/null; then
  SET="$TMP/photocraft.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    render "$MAC" "$s" "$SET/icon_${s}x${s}.png"
    render "$MAC" $((s * 2)) "$SET/icon_${s}x${s}@2x.png"
  done
  iconutil -c icns -o "$DIR/photocraft.icns" "$SET"
else
  echo "warning: iconutil not found (macOS only); photocraft.icns not regenerated" >&2
fi
echo "icons written to $DIR"
