#!/usr/bin/env bash
# Build and (re)launch MTAMenu.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "${1:-release}"
pkill -x MTAMenu 2>/dev/null || true
open build/MTAMenu.app
echo "MTAMenu is running — look for the subway icon in your menu bar."
