#!/usr/bin/env bash
# Point this repo at .githooks/ so `git commit` runs full local CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

chmod +x .githooks/pre-commit scripts/ci-local.sh
git config core.hooksPath .githooks

echo "Installed Git hooks (core.hooksPath=.githooks)."
echo "Commits run full local CI for touched platforms (same as GitHub iOS/Android workflows)."
echo "Manual: make ci-local | make ci-local-ios | make ci-local-android"
echo "Skip once: DIVERGE_SKIP_LOCAL_CI=1 git commit ..."
