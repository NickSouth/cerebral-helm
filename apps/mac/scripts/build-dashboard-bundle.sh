#!/usr/bin/env bash
#
# Builds the production dashboard and stages it into the macOS app bundle inputs
# (NIC-73 / FR-SHL-03). The Xcode target bundles `apps/mac/DashboardBundle/` as a
# folder reference into `Contents/Resources/DashboardBundle`, which the shell serves
# offline over the `cerebral://app/` scheme. Run this before building the app; the
# bundle output is generated (gitignored), not committed.
#
# Usage: apps/mac/scripts/build-dashboard-bundle.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
dashboard="$repo/apps/dashboard"
out="$repo/apps/mac/DashboardBundle"

echo "› Building production dashboard (no dev server)…"
pnpm --dir "$dashboard" build

echo "› Staging dist → $out"
rm -rf "$out"
mkdir -p "$out"
cp -R "$dashboard/dist/." "$out/"
touch "$out/.gitkeep"

echo "✓ Dashboard bundle ready: $(cd "$out" && find . -type f | wc -l | tr -d ' ') files"
