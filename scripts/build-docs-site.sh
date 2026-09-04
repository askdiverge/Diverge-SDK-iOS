#!/usr/bin/env bash
# Build DocC for AIConversation and assemble Docs/site into site-dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-AIConversation}"
# Only the public product is published; the engine/core targets are implementation detail.
DOC_TARGET="${DOC_TARGET:-AIConversation}"
SITE_DIST="${SITE_DIST:-$ROOT/site-dist}"
DOCS_OUT="${DOCS_OUT:-$ROOT/docs-out}"
DERIVED="${DERIVED:-$ROOT/.docc-build}"
rm -rf "$SITE_DIST" "$DOCS_OUT" "$DERIVED"
mkdir -p "$DOCS_OUT" "$SITE_DIST"

# DocC ships with the toolchain; xcodebuild emits the archive and `docc process-archive`
# does the static-hosting transform, so no docc plugin dependency is needed.
generate_docc() {
  local target="$1"
  local base_path="$2"

  echo "Generating DocC for ${target}..."
  xcodebuild docbuild \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    >/dev/null

  local archive
  archive="$(find "$DERIVED" -type d -name "${target}.doccarchive" -print -quit)"
  [[ -n "$archive" ]] || { echo "error: no ${target}.doccarchive produced" >&2; exit 1; }

  xcrun docc process-archive transform-for-static-hosting "$archive" \
    --output-path "$DOCS_OUT/${target}.doccarchive" \
    --hosting-base-path "$base_path"
}

generate_docc "$DOC_TARGET" "documentation/$(echo "$DOC_TARGET" | tr '[:upper:]' '[:lower:]')"

# Static marketing / guides site first
cp -R "$ROOT/Docs/site/." "$SITE_DIST/"

# Custom domain for GitHub Pages (DNS still human-owned)
printf 'docs.askdiverge.ai\n' > "$SITE_DIST/CNAME"

# Merge transformed DocC trees so hosting-base-path URLs resolve from site root.
rsync -a "$DOCS_OUT/$DOC_TARGET.doccarchive/documentation/" "$SITE_DIST/documentation/"
for asset in css js data img images index downloads videos; do
  if [[ -d "$DOCS_OUT/$DOC_TARGET.doccarchive/$asset" ]]; then
    mkdir -p "$SITE_DIST/$asset"
    rsync -a "$DOCS_OUT/$DOC_TARGET.doccarchive/$asset/" "$SITE_DIST/$asset/"
  fi
done

# Raw .doccarchive trees are kept under docs-out/ for local use only.
# Do not copy them into site-dist — they duplicate data/ and include the same
# operator-symbol filenames that break GitHub Actions artifact uploads.

# GitHub Actions artifacts / Pages reject NTFS-illegal path characters.
# DocC names some operator overloads with ':' in *directory* and file names
# (e.g. documentation/.../!=(_:_:)/index.html).
SITE_DIST="$SITE_DIST" python3 - <<'PY'
import os
import shutil
from pathlib import Path

illegal = set('":<>|*?\r\n')
root = Path(os.environ["SITE_DIST"])


def path_has_illegal(rel: Path) -> bool:
    return any(any(ch in part for ch in illegal) for part in rel.parts)


removed = []

# Remove files whose relative path contains an illegal component.
for path in list(root.rglob("*")):
    if not path.is_file():
        continue
    rel = path.relative_to(root)
    if path_has_illegal(rel):
        removed.append(rel.as_posix())
        path.unlink(missing_ok=True)

# Remove directories with illegal names (deepest first).
dirs = [
    p for p in root.rglob("*")
    if p.is_dir() and any(ch in p.name for ch in illegal)
]
dirs.sort(key=lambda p: len(p.parts), reverse=True)
for directory in dirs:
    if directory.exists():
        removed.append(directory.relative_to(root).as_posix() + "/")
        shutil.rmtree(directory, ignore_errors=True)

print(f"Removed {len(removed)} artifact-incompatible DocC path(s)")
for rel in removed[:30]:
    print(f"  - {rel}")
if len(removed) > 30:
    print(f"  … and {len(removed) - 30} more")
PY

echo "Site assembled at $SITE_DIST"
# Archives remain available locally for inspection:
echo "DocC archives (local only): $DOCS_OUT"

# Fail if published HTML still points outside site-dist with relative ../ links
# (those 404 on GitHub Pages). Prefer absolute GitHub or same-directory hrefs.
bad_links="$(
  grep -RInE 'href="\.\./' "$SITE_DIST" --include='*.html' || true
)"
if [[ -n "$bad_links" ]]; then
  echo "error: Docs/site HTML contains relative parent links that break on Pages:" >&2
  echo "$bad_links" >&2
  exit 1
fi
echo "Pages link check: no relative ../ hrefs in site-dist HTML"
