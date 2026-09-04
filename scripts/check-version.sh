#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
fail=0
check_contains() {
  local file="$1" pattern="$2"
  [[ -f "$file" ]] || { echo "Missing $file"; fail=1; return; }
  grep -qE "$pattern" "$file" || { echo "Mismatch $file"; fail=1; }
}
check_contains "$ROOT/Sources/AIConversation/Version.swift" "static let current = \"$VERSION\""
check_contains "$ROOT/README.md" "from: \"${VERSION}\""
check_contains "$ROOT/Samples/iOS/Sample.xcodeproj/project.pbxproj" "MARKETING_VERSION = ${VERSION};"
[[ "$fail" -eq 0 ]] || { echo "Run ./scripts/sync-version.sh"; exit 1; }
echo "Version check passed ($VERSION)"
