#!/usr/bin/env sh
set -eu

# Copy the freshly built RuoYi Vue distribution into the Spring Boot static
# directory while preserving the embedded Warm-Flow designer bundle.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
UI_DIST="$APP_DIR/ruoyi-ui/dist"
STATIC_DIR="$APP_DIR/ruoyi-admin/src/main/resources/static"
PRESERVE_DIR="$STATIC_DIR/warm-flow-ui"
PRESERVE_TMP="$APP_DIR/.warm-flow-ui-preserve.$$"

cleanup() {
  rm -rf "$PRESERVE_TMP"
}
trap cleanup EXIT INT TERM

if [ ! -d "$UI_DIST" ]; then
  echo "RuoYi UI dist not found: $UI_DIST" >&2
  echo "Run: (cd ruoyi-ui && npm ci --no-audit --no-fund && npm run build:prod)" >&2
  exit 1
fi

mkdir -p "$STATIC_DIR"
if [ -d "$PRESERVE_DIR" ]; then
  cp -R "$PRESERVE_DIR" "$PRESERVE_TMP"
fi

find "$STATIC_DIR" -mindepth 1 -maxdepth 1 ! -name 'warm-flow-ui' -exec rm -rf {} +
cp -R "$UI_DIST"/. "$STATIC_DIR"/

if [ -d "$PRESERVE_TMP" ]; then
  rm -rf "$PRESERVE_DIR"
  cp -R "$PRESERVE_TMP" "$PRESERVE_DIR"
fi

echo "Synced RuoYi UI static assets into $STATIC_DIR"
