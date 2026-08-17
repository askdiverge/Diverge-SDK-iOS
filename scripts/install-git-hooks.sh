#!/usr/bin/env bash
# Point this repo at .githooks/ so `git commit` runs full local CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

chmod +x .githooks/pre-commit scripts/ci-local.sh
git config core.hooksPath .githooks

echo "Installed Git hooks (core.hooksPath=.githooks)."
echo "Commits run local CI for staged iOS paths (same as GitHub iOS workflow)."
echo "Manual: make ci-local"
echo "Skip once: DIVERGE_SKIP_LOCAL_CI=1 git commit ..."
