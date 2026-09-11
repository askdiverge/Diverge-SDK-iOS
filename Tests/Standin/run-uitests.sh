#!/usr/bin/env bash
# Drive the Sample app against the stand-in Chatbot API.
# Usage:
#   ./Tests/Standin/run-uitests.sh              # every suite
#   ./Tests/Standin/run-uitests.sh HistoryTests  # one class
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STANDIN="$(cd "$(dirname "$0")" && pwd)"
SERVERS="$STANDIN/servers"
PORT="${PORT:-3000}"
# Not `SCHEME`: that name is generic enough for a wrapper or CI env to set it
# for a different project, which would point xcodebuild at a missing scheme.
SCHEME="${UITEST_SCHEME:-DriverApp}"
PROJECT="$STANDIN/Driver.xcodeproj"
SAMPLE_PROJECT="$ROOT/Samples/iOS/Sample.xcodeproj"
DERIVED="${DERIVED_DATA_PATH:-$ROOT/.build/uitest-derived}"

cd "$ROOT"

suite_server() {
  case "$1" in
    DriveTests) echo "server.py" ;;
    PhotoTests) echo "photo_server.py" ;;
    HistoryTests) echo "history_server.py" ;;
    UploadPromptTests) echo "upload_prompt_server.py" ;;
    UploadPromptDisabledTests) echo "upload_prompt_server.py" ;;
    StartPromptsTests) echo "start_prompts_server.py" ;;
    ProductActionsTests) echo "product_actions_server.py" ;;
    DarkAppearanceTests) echo "dark_theme_server.py" ;;
    DownloadDataTests) echo "export_server.py" ;;
    BannerTests) echo "banners_server.py" ;;
    *) echo ""; return 1 ;;
  esac
}

suite_env() {
  # Printed as KEY=value tokens the runner evals before launching the server.
  case "$1" in
    HistoryTests) echo "DELAY=6 FAIL_ONCE=c2 SHAPE=nonalt" ;;
    UploadPromptTests) echo "TAIL_DELAY=6" ;;
    UploadPromptDisabledTests) echo "SEED_MARKER_ONLY=1" ;;
    *) echo "" ;;
  esac
}

ALL_SUITES=(
  DriveTests
  PhotoTests
  HistoryTests
  UploadPromptTests
  UploadPromptDisabledTests
  StartPromptsTests
  ProductActionsTests
  DarkAppearanceTests
  DownloadDataTests
  BannerTests
)

resolve_destination() {
  local dest=""
  if [[ -n "${DESTINATION:-}" ]]; then
    echo "$DESTINATION"
    return 0
  fi
  dest="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null |
    awk -F'[{}]' '
      /platform:iOS Simulator/ && /name:iPhone/ && /id:/ && !/error:/ && !/dvtdevice-/ {
        gsub(/^ +| +$/, "", $2)
        print $2
        exit
      }
    '
  )"
  local id
  id="$(echo "$dest" | sed -n 's/.*id:\([^,]*\).*/\1/p' | tr -d ' ')"
  if [[ -z "$id" ]]; then
    echo "error: no iPhone Simulator destination for $SCHEME" >&2
    return 1
  fi
  echo "platform=iOS Simulator,id=${id}"
}

destination_udid() {
  echo "$1" | sed -n 's/.*id=\([^,]*\).*/\1/p'
}

listeners() {
  # `-sTCP:LISTEN` so client sockets are left alone — the Sample app under test
  # holds one to :$PORT, and killing that takes down the run.
  lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null || true
}

# Leave :$PORT with nothing listening. Returning while the previous stand-in
# still holds it makes the next one exit on bind, and the readiness probe would
# then answer from the dying server.
kill_port() {
  local pids i
  for i in $(seq 1 40); do
    pids="$(listeners)"
    if [[ -z "$pids" ]]; then
      return 0
    fi
    if [[ $i -gt 10 ]]; then
      # shellcheck disable=SC2086
      kill -9 $pids 2>/dev/null || true
    else
      # shellcheck disable=SC2086
      kill $pids 2>/dev/null || true
    fi
    sleep 0.25
  done
  echo "error: :$PORT still has a listener after 10s" >&2
  return 1
}

# A bound socket is not a served request: `lsof` also matches a listener that is
# not accepting yet, and the app's bootstrap then times out instead of failing
# fast. Probe over HTTP — any status proves the handler ran. `/__ready` is
# unrouted everywhere, so it 404s without touching the seeded state tests assert on.
wait_for_server() {
  local pid="$1" i code
  for i in $(seq 1 300); do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "error: stand-in exited before serving — see /tmp/diverge-standin/*.server.log" >&2
      return 1
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$PORT/__ready" 2>/dev/null || true)"
    if [[ -n "$code" && "$code" != "000" ]]; then
      return 0
    fi
    sleep 0.2
  done
  echo "error: stand-in did not answer on :$PORT within 60s" >&2
  return 1
}

install_sample() {
  local dest="$1"
  echo "==> Build Sample (Local) for $dest"
  xcodebuild build \
    -project "$SAMPLE_PROJECT" \
    -scheme Sample \
    -configuration Local \
    -destination "$dest" \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO

  local app
  app="$(find "$DERIVED" -name Sample.app -type d \( -path '*/Local-iphonesimulator/*' -o -path '*/Debug-iphonesimulator/*' \) -print -quit)"
  if [[ -z "$app" ]]; then
    echo "error: Sample.app not found under $DERIVED" >&2
    return 1
  fi

  local udid
  udid="$(destination_udid "$dest")"
  echo "==> Install Sample on $udid"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$app"
}

run_one() {
  local suite="$1"
  local dest="$2"
  local server
  server="$(suite_server "$suite")"
  local extra
  extra="$(suite_env "$suite")"

  echo "==> $suite  ($server ${extra})"
  kill_port || return 1
  mkdir -p /tmp/diverge-standin

  # shellcheck disable=SC2086
  env PORT="$PORT" $extra python3 -u "$SERVERS/$server" >"/tmp/diverge-standin/${suite}.server.log" 2>&1 &
  local pid=$!
  if ! wait_for_server "$pid"; then
    kill "$pid" 2>/dev/null || true
    return 1
  fi

  local status=0
  # xcodebuild forwards TEST_RUNNER_-prefixed variables to the runner with the
  # prefix stripped; the appearance suite needs the destination's udid, and
  # `simctl`'s "booted" alias is ambiguous once a second simulator is up.
  TEST_RUNNER_SIM_UDID="$(destination_udid "$dest")" \
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$dest" \
    -only-testing:"DriverUITests/${suite}" \
    -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO \
    || status=$?

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  kill_port
  return "$status"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '1,6p' "$0"
  echo "Suites: ${ALL_SUITES[*]}"
  exit 0
fi

DEST="$(resolve_destination)"
echo "Using destination: $DEST"
mkdir -p /tmp/diverge-standin
install_sample "$DEST"

suites=("$@")
if [[ ${#suites[@]} -eq 0 ]]; then
  suites=("${ALL_SUITES[@]}")
fi

failed=()
for suite in "${suites[@]}"; do
  if ! suite_server "$suite" >/dev/null; then
    echo "error: unknown suite $suite" >&2
    exit 2
  fi
  if ! run_one "$suite" "$DEST"; then
    failed+=("$suite")
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "UITests failed: ${failed[*]}" >&2
  exit 1
fi
echo "==> UITests ok (${#suites[@]} suite(s))"
