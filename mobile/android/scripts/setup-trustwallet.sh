#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROPS="$ROOT/local.properties"

GITHUB_USER="${1:-${GITHUB_USER:-}}"
GITHUB_TOKEN="${2:-${GITHUB_TOKEN:-}}"

if [[ -z "$GITHUB_USER" ]]; then
  read -r -p "GitHub username: " GITHUB_USER
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo ""
  echo "Create a read-only token at:"
  echo "  https://github.com/settings/tokens/new?scopes=read:packages&description=Mesh%20Wallet%20Android"
  echo ""
  read -r -s -p "GitHub token (read:packages): " GITHUB_TOKEN
  echo ""
fi

touch "$PROPS"

# Remove old gpr entries if present
grep -v '^gpr\.' "$PROPS" > "$PROPS.tmp" 2>/dev/null || true
mv "$PROPS.tmp" "$PROPS"

{
  echo "gpr.user=$GITHUB_USER"
  echo "gpr.key=$GITHUB_TOKEN"
} >> "$PROPS"

echo "Saved gpr.user / gpr.key to local.properties"
echo "Run: ./gradlew :app:assembleDebug"
