# Operator runbook: canary / beta GitHub Release (iOS)

**Status:** release workflow supports prerelease tags; this runbook is how to smoke-test the channel. Do not push tags from CI automation in this pass unless an operator explicitly chooses to.

## Tag conventions

| Channel | Tag pattern | GitHub Release |
|---------|-------------|----------------|
| Stable | `vMAJOR.MINOR.PATCH` | `prerelease: false` |
| Beta | `vMAJOR.MINOR.PATCH-beta.N` | `prerelease: true` |
| Canary | `vMAJOR.MINOR.PATCH-canary.N` | `prerelease: true` |

Enforced by [`.github/workflows/release.yml`](../../.github/workflows/release.yml).

## Preconditions

1. Root `VERSION` matches the **base** SemVer (e.g. tag `v0.1.0-canary.1` ⇒ `VERSION` = `0.1.0`).
2. `CHANGELOG.md` has `## [0.1.0]` or `## [0.1.0-canary.1]`.
3. `./scripts/check-version.sh` passes.
4. `main` (or the commit you tag) is green on the `iOS` workflow.

## Smoke steps (operator)

```bash
# On the commit to publish:
git tag v0.1.0-canary.1
git push origin v0.1.0-canary.1
```

Then confirm:

1. Actions → **Release** workflow succeeds.
2. GitHub Releases shows `v0.1.0-canary.1` marked as **Pre-release**.
3. A consumer can resolve SPM with `.package(..., from: "0.1.0-canary.1")` or an exact version rule for that tag.

## Rollback

Delete the GitHub Release and the remote tag if the smoke fails. Do not reuse the same canary number after a bad publish; bump `N`.
