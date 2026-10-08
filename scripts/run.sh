#!/usr/bin/env bash
# Build and (re)launch SubwayMenuBar.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "${1:-release}"
pkill -x SubwayMenuBar 2>/dev/null || true
open build/SubwayMenuBar.app
echo "SubwayMenuBar is running — look for the subway icon in your menu bar."
