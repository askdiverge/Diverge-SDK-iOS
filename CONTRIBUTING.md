# Contributing to Diverge SDK

Thanks for contributing. This guide covers the scaffold-era workflow; expand it as the SDK API stabilizes.

## Development setup

Install local Git hooks once (runs **full local CI** on every `git commit` for touched platforms):

```bash
make install-hooks
# or: ./scripts/install-git-hooks.sh
```

The pre-commit hook mirrors GitHub Actions:

- Always: `./scripts/check-version.sh`
- iOS paths staged → same as `.github/workflows/ios.yml` (SwiftLint, SwiftFormat, `xcodebuild test` on `DivergeSDK-Package`, sample build)
- Android paths staged → same as `.github/workflows/android.yml` (assemble, test, lint, Dokka, release minify, R8 keeps)

Run without committing:

```bash
make ci-local          # both platforms
make ci-local-ios
make ci-local-android
```

Skip once: `DIVERGE_SKIP_LOCAL_CI=1 git commit -m "..."`.

Common commands (also see `make help`):

```bash
make sync-version
make check-version
make ios-test
make android-test
```

Keep the root `VERSION` file as the single source of truth:

```bash
./scripts/sync-version.sh   # updates generated Swift + docs/README placeholders
./scripts/check-version.sh  # fails if sources drift
```

Android modules read `VERSION` at Gradle configure time (no sync step required for Kotlin).

### iOS

1. Install Xcode 26+ and Command Line Tools.
2. Optional: [SwiftLint](https://github.com/realm/SwiftLint) and [SwiftFormat](https://github.com/nicklockwood/SwiftFormat).
3. From the repo root:

```bash
swift test
swiftformat --lint .
swiftlint lint
```

Open `Package.swift` or `Samples/iOS/DivergeSample.xcodeproj` in Xcode for simulator runs.

### Android

1. Install JDK 17 and Android SDK (`ANDROID_HOME`).
2. From `android/`:

```bash
./gradlew :diverge-sdk:assemble :diverge-sdk:test :diverge-sdk:lint :diverge-sdk:dokkaHtml :diverge-sdk:dokkaJavadoc
./gradlew :sample:assembleDebug
```

## Branching and PRs

- Open PRs against `main`.
- Keep changes focused; include tests when behavior changes.
- Fill in the PR template when present.
- **Local:** `make install-hooks` then every `git commit` runs full local CI for touched platforms (`scripts/ci-local.sh`, mirrors GitHub iOS/Android).
- **Remote:** path-filtered GitHub Actions (`iOS`, `Android`, `DocC`) on push/PR.

## Releases

1. Bump `VERSION`, run `./scripts/sync-version.sh`, update `CHANGELOG.md` with `## [x.y.z]`.
2. For breaking changes, add `Docs/integration/vX.Y.Z.md` from [`Dev-Docs/integration/TEMPLATE.md`](Dev-Docs/integration/TEMPLATE.md).
3. Tag with SemVer: `vMAJOR.MINOR.PATCH`, or `vX.Y.Z-beta.N` / `vX.Y.Z-canary.N`.
4. Push the tag; `.github/workflows/release.yml` validates SemVer, VERSION, changelog, then creates the GitHub Release.

## Code style

- Swift: SwiftFormat + SwiftLint configs at the repo root (`--header ignore`).
- Kotlin: Android Studio defaults; CI runs lint with `abortOnError`.

## Package.resolved

Committed on purpose — see [`Dev-Docs/PACKAGE_RESOLVED.md`](Dev-Docs/PACKAGE_RESOLVED.md).

## Products

| Product | Contents |
|---------|----------|
| `DivergeSDK` | Core configure/client API (no SwiftUI) |
| `DivergeSDKUI` | ``DivergeStatusView`` and related SwiftUI helpers |

## Strict Concurrency

The library and tests use Swift 6 language mode. Keep new API `Sendable`-safe; `Diverge.configure` / `shared` use a lock plus `nonisolated(unsafe)` for the shared client slot.

## License

By contributing, you agree that your contributions are licensed under the Apache License, Version 2.0.
