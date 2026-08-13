#!/usr/bin/env bash
# Verify VERSION matches generated/synced sources (iOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

fail=0

check_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "$file" ]]; then
    echo "Missing file: $file" >&2
    fail=1
    return
  fi
  if ! grep -qE "$pattern" "$file"; then
    echo "Version mismatch in $file (expected $VERSION)" >&2
    fail=1
  fi
}

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]]; then
  echo "Invalid VERSION: $VERSION" >&2
  fail=1
fi

check_contains "$ROOT/Sources/DivergeSDK/Version.swift" "static let current = \"$VERSION\""
check_contains "$ROOT/Docs/site/index.html" "v${VERSION}"
check_contains "$ROOT/Docs/site/getting-started.html" "from: \"${VERSION}\""
check_contains "$ROOT/README.md" "from: \"${VERSION}\""
check_contains "$ROOT/Samples/iOS/DivergeSample.xcodeproj/project.pbxproj" "MARKETING_VERSION = ${VERSION};"
check_contains "$ROOT/Samples/iOS/project.yml" "MARKETING_VERSION: \"${VERSION}\""

if [[ "$fail" -ne 0 ]]; then
  echo "Run: ./scripts/sync-version.sh" >&2
  exit 1
fi

echo "Version check passed ($VERSION)"
