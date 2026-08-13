#!/usr/bin/env bash
# Local CI mirroring .github/workflows/ios.yml and android.yml.
# Usage:
#   ./scripts/ci-local.sh           # version + ios + android
#   ./scripts/ci-local.sh ios       # version + ios
#   ./scripts/ci-local.sh android   # version + android
#   ./scripts/ci-local.sh version   # version only
#
# Escape hatch: DIVERGE_SKIP_LOCAL_CI=1 skips everything (pre-commit only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="${1:-all}"

if [[ "${DIVERGE_SKIP_LOCAL_CI:-}" == "1" ]]; then
  echo "DIVERGE_SKIP_LOCAL_CI=1 set — skipping local CI"
  exit 0
fi

# Resolve an xcodebuild -destination for a scheme.
# Prefers an iPhone simulator listed for that scheme.
# If allow_macos=1 and no iOS Simulator is available, falls back to macOS
# (useful for SPM package tests when the local iOS platform isn't installed).
resolve_destination() {
  local scheme="$1"
  local project="${2:-}"
  local allow_macos="${3:-0}"
  local list_args=()
  local dest=""
  local id=""
  local name=""

  if [[ -n "$project" ]]; then
    list_args+=(-project "$project")
  fi
  list_args+=(-scheme "$scheme" -showdestinations)

  xcodebuild "${list_args[@]}" 2>/dev/null | tee /tmp/xcode-destinations.txt >/dev/null || true

  dest="$(
    awk -F'[{}]' '
      /platform:iOS Simulator/ && /name:iPhone/ && /id:/ && !/error:/ {
        gsub(/^ +| +$/, "", $2)
        print $2
        exit
      }
    ' /tmp/xcode-destinations.txt
  )"

  if [[ -n "$dest" ]]; then
    id="$(echo "$dest" | sed -n 's/.*id:\([^,]*\).*/\1/p' | tr -d ' ')"
    if [[ -n "$id" ]]; then
      echo "platform=iOS Simulator,id=${id}"
    else
      name="$(echo "$dest" | sed -n 's/.*name:\([^,]*\).*/\1/p' | sed 's/^ *//;s/ *$//')"
      echo "platform=iOS Simulator,name=${name:-iPhone 16}"
    fi
    return
  fi

  if [[ "$allow_macos" == "1" ]] && grep -q 'platform:macOS' /tmp/xcode-destinations.txt; then
    echo "platform=macOS,arch=arm64"
    return
  fi

  return 1
}

run_version() {
  echo "==> CI local: version sync"
  ./scripts/check-version.sh
}

run_ios() {
  echo "==> CI local: iOS (mirrors .github/workflows/ios.yml)"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: iOS CI requires macOS + Xcode" >&2
    exit 1
  fi
  if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: swiftlint not found. Install with: brew install swiftlint" >&2
    exit 1
  fi
  if ! command -v swiftformat >/dev/null 2>&1; then
    echo "error: swiftformat not found. Install with: brew install swiftformat" >&2
    exit 1
  fi
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found. Install Xcode." >&2
    exit 1
  fi

  echo "==> SwiftLint"
  swiftlint lint --strict

  echo "==> SwiftFormat"
  swiftformat --lint .

  echo "==> Resolve package"
  swift package resolve
  xcodebuild -list -scheme DivergeSDK-Package >/dev/null || xcodebuild -list >/dev/null

  local pkg_dest sample_dest
  # Product scheme "DivergeSDK" has no Test action; SPM tests live on "*-Package".
  if ! pkg_dest="$(resolve_destination DivergeSDK-Package "" 1)"; then
    echo "error: no usable destination for DivergeSDK-Package" >&2
    echo "Install the iOS platform via Xcode → Settings → Components, or ensure macOS is available." >&2
    exit 1
  fi
  echo "==> Package tests ($pkg_dest) [scheme DivergeSDK-Package]"
  xcodebuild test \
    -scheme DivergeSDK-Package \
    -destination "$pkg_dest" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

  if ! sample_dest="$(resolve_destination DivergeSample Samples/iOS/DivergeSample.xcodeproj 0)"; then
    echo "error: no iOS Simulator destination for DivergeSample." >&2
    echo "" >&2
    echo "A booted Simulator app is not enough: this Xcode only accepts destinations" >&2
    echo "listed by \`xcodebuild -showdestinations\` for the scheme. Right now that" >&2
    echo "list has no iOS Simulator entries — typically because the matching iOS" >&2
    echo "platform/runtime is missing (e.g. iOS 26.x for Xcode 26)." >&2
    echo "" >&2
    echo "Fix (pick one):" >&2
    echo "  1. Xcode → Settings → Components → download/install iOS" >&2
    echo "  2. xcodebuild -downloadPlatform iOS" >&2
    echo "Then create/boot a simulator on that runtime and re-run: make ci-local-ios" >&2
    if grep -q 'iOS .* is not installed' /tmp/xcode-destinations.txt 2>/dev/null; then
      echo "" >&2
      echo "Xcode hint from showdestinations:" >&2
      grep -o 'error:[^}]*' /tmp/xcode-destinations.txt 2>/dev/null | head -3 | sed 's/^/  /' >&2 || true
    fi
    exit 1
  fi
  echo "==> Build iOS sample ($sample_dest)"
  xcodebuild build \
    -project Samples/iOS/DivergeSample.xcodeproj \
    -scheme DivergeSample \
    -destination "$sample_dest" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

  echo "==> CI local: iOS ok"
}

run_android() {
  echo "==> CI local: Android (mirrors .github/workflows/android.yml)"

  if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
    echo "error: ANDROID_HOME (or ANDROID_SDK_ROOT) not set" >&2
    exit 1
  fi
  if ! command -v java >/dev/null 2>&1; then
    echo "error: java not found (need JDK 17+)" >&2
    exit 1
  fi

  (
    cd android
    ./gradlew \
      :diverge-sdk:assemble \
      :diverge-sdk:test \
      :diverge-sdk:lint \
      :diverge-sdk:dokkaHtml \
      :diverge-sdk:dokkaJavadoc \
      :sample:assembleDebug \
      :sample:assembleRelease \
      :sample:verifyR8PublicApiKeeps \
      :sample:testDebugUnitTest \
      --stacktrace
  )

  echo "==> CI local: Android ok"
}

case "$MODE" in
  version)
    run_version
    ;;
  ios)
    run_version
    run_ios
    ;;
  android)
    run_version
    run_android
    ;;
  all)
    run_version
    run_ios
    run_android
    ;;
  *)
    echo "usage: $0 [all|ios|android|version]" >&2
    exit 2
    ;;
esac

echo "==> CI local: passed ($MODE)"
