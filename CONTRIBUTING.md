# Contributing to Diverge SDK (iOS)

Thanks for contributing. This repository is **iOS-only** (Swift Package Manager). Android lives in [Diverge-SDK-Android](https://github.com/askdiverge/Diverge-SDK-Android).

## Development setup

Install local Git hooks once (runs local CI on `git commit` when iOS paths are staged):

```bash
make install-hooks
# or: ./scripts/install-git-hooks.sh
```

The pre-commit hook mirrors GitHub Actions:

- Always: `./scripts/check-version.sh`
- iOS paths staged → same as `.github/workflows/ios.yml` (SwiftLint, SwiftFormat, package tests, sample build)

Run without committing:

```bash
make ci-local
```

Skip once: `DIVERGE_SKIP_LOCAL_CI=1 git commit -m "..."`.

Common commands:

```bash
make sync-version
make check-version
make ios-test
make ios-lint
make docs-docc
```

Keep the root `VERSION` file as the single source of truth:

```bash
./scripts/sync-version.sh   # updates generated Swift + docs placeholders
./scripts/check-version.sh  # fails if sources drift
```

### Tooling

1. Install Xcode 26+ (CI uses the newest stable Xcode on `macos-26`; do not pin an older default) and Command Line Tools.
2. Optional: [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat).
3. From the repo root:

```bash
swift test
swiftformat --lint .
swiftlint lint --strict
```

Open `Package.swift` or `Samples/iOS/DivergeSample.xcodeproj` in Xcode for simulator runs (iOS 18+).

## Branching and PRs

- Open PRs against `main`.
- Keep changes focused; include tests when behavior changes.
- Fill in the PR template when present.
- **Local:** `make install-hooks` then every `git commit` runs local CI for staged iOS paths.
- **Remote:** path-filtered GitHub Actions (`iOS`, `DocC`, `release`) on push/PR/tags.

## Releases

1. Bump `VERSION`, run `./scripts/sync-version.sh`, update `CHANGELOG.md` with `## [x.y.z]`.
2. For breaking changes, add `Docs/integration/vX.Y.Z.md` from [`Docs/integration/TEMPLATE.md`](Docs/integration/TEMPLATE.md).
3. Tag with SemVer: `vMAJOR.MINOR.PATCH`, or `vX.Y.Z-beta.N` / `vX.Y.Z-canary.N`.
4. Push the tag; `.github/workflows/release.yml` validates SemVer, VERSION, changelog, then creates the GitHub Release.

See also [`Docs/ops/canary-release.md`](Docs/ops/canary-release.md).

## Code style

SwiftFormat + SwiftLint configs at the repo root (`--header ignore`).

## Package.resolved

Committed on purpose — see [`Docs/dev/PACKAGE_RESOLVED.md`](Docs/dev/PACKAGE_RESOLVED.md).

## Products

| Product | Contents |
|---------|----------|
| `DivergeSDK` | Core configure/client API (no SwiftUI) |
| `DivergeSDKUI` | `DivergeStatusView` and related SwiftUI helpers |

## Strict Concurrency

The library and tests use Swift 6 language mode. Keep new API `Sendable`-safe; `Diverge.configure` / `shared` use a lock plus `nonisolated(unsafe)` for the shared client slot.

## License

By contributing, you agree that your contributions are licensed under the Apache License, Version 2.0.
