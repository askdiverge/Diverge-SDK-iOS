# Integration guides

Per-release guides for host apps integrating the **iOS** Diverge SDK.

| File | Purpose |
|------|---------|
| [`TEMPLATE.md`](TEMPLATE.md) | Skeleton for a new release guide |
| [`v0.1.0.md`](v0.1.0.md) | Baseline public surface (stay on 0.1.0 until API is stable) |

## Process (every tagged release)

1. Bump `VERSION`, run `./scripts/sync-version.sh`, update root `CHANGELOG.md`.
2. If there are breaking changes or migration steps, copy `TEMPLATE.md` → `vX.Y.Z.md` and fill it in.
3. Update the GitHub Release body from [`../releases/RELEASE_NOTES_TEMPLATE.md`](../releases/RELEASE_NOTES_TEMPLATE.md).
4. Tag `vX.Y.Z` (or beta/canary) and push — see [`../ops/canary-release.md`](../ops/canary-release.md).
