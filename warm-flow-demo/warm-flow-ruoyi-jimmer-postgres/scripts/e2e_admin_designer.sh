#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NODE_BIN=${NODE_BIN:-node}
NPM_BIN=${NPM_BIN:-npm}
PLAYWRIGHT_VERSION=${PLAYWRIGHT_VERSION:-1.57.0}
PLAYWRIGHT_INSTALL_DEPS=${PLAYWRIGHT_INSTALL_DEPS:-false}
PLAYWRIGHT_TMP_DIR=${PLAYWRIGHT_TMP_DIR:-${TMPDIR:-/tmp}/warm-flow-playwright-runtime}

if "$NODE_BIN" -e "require.resolve('playwright')" >/dev/null 2>&1; then
  exec "$NODE_BIN" "$SCRIPT_DIR/e2e_admin_designer.js" "$@"
fi

mkdir -p "$PLAYWRIGHT_TMP_DIR"
if [ ! -f "$PLAYWRIGHT_TMP_DIR/package.json" ]; then
  (cd "$PLAYWRIGHT_TMP_DIR" && "$NPM_BIN" init -y >/dev/null)
fi
(cd "$PLAYWRIGHT_TMP_DIR" && "$NPM_BIN" install "playwright@$PLAYWRIGHT_VERSION" >/dev/null)

# Ensure the browser binary exists when the cache is new. The command is safe to
# rerun and keeps browser downloads outside this repository. GitHub-hosted Linux
# runners can opt into OS dependency installation with PLAYWRIGHT_INSTALL_DEPS=true.
if [ "$PLAYWRIGHT_INSTALL_DEPS" = "true" ]; then
  (cd "$PLAYWRIGHT_TMP_DIR" && npx playwright install --with-deps chromium >/dev/null)
else
  (cd "$PLAYWRIGHT_TMP_DIR" && npx playwright install chromium >/dev/null)
fi

export NODE_PATH="$PLAYWRIGHT_TMP_DIR/node_modules${NODE_PATH:+:$NODE_PATH}"
exec "$NODE_BIN" "$SCRIPT_DIR/e2e_admin_designer.js" "$@"
