#!/usr/bin/env bash
set -euo pipefail

echo "Reinstalling/opening stable app with fresh Accessibility state..."
"$(cd "$(dirname "$0")/.." && pwd)/scripts/install-app.sh" --fresh-permissions

echo "Now click KyB → Request, or enable KyB in System Settings → Privacy & Security → Accessibility."
echo "If prompted, macOS/Settings owns password/Touch ID prompt; KyB cannot force that prompt."
