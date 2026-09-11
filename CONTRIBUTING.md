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
- iOS paths staged → SwiftLint, package tests, sample build (`./scripts/ci-local.sh`). The GitHub `uitest` job is not in the hook — run `make uitest` locally when you touch Sample / stand-in suites.

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
make uitest            # stand-in XCUITests (needs an iOS Simulator; not in pre-commit)
```

Keep the root `VERSION` file as the single source of truth:

```bash
./scripts/sync-version.sh   # updates generated Swift + docs placeholders
./scripts/check-version.sh  # fails if sources drift
```

### Tooling

1. Install Xcode 26+ (CI uses the newest stable Xcode on `macos-26`; do not pin an older default) and Command Line Tools.
2. Optional: [SwiftLint](https://github.com/realm/SwiftLint).
3. From the repo root:

```bash
swift test
swiftlint lint --strict
```

Open `Package.swift` or `Samples/iOS/Sample.xcodeproj` in Xcode for simulator runs (iOS 18+).
Stand-in XCUITests: `make uitest` (see [`Tests/Standin/README.md`](Tests/Standin/README.md)).
CI runs them after package tests (job `uitest`); they are not in the pre-commit hook.

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

SwiftLint config at the repo root (`.swiftlint.yml`) is the single source of style truth.

### File and type size

One type, or one concern of a type, per file. SwiftLint enforces it and CI lints `--strict`, so
the warning threshold is the effective limit (counts exclude comment-only and blank lines):

| Scope                     | `file_length`        | `type_body_length`   | `function_body_length` |
| ------------------------- | -------------------- | -------------------- | ---------------------- |
| `Sources/`, `Samples/`    | warn 250 / error 400 | warn 200 / error 350 | warn 60 / error 100    |
| `Tests/` (nested config)  | warn 400 / error 600 | warn 350 / error 500 | warn 60 / error 100    |

When a file approaches the limit, split by concern rather than trimming comments:

- Behaviour of a type → `extension` files named `Type+Concern.swift`
  (`ChatView+ViewModel+Send.swift`, `ChatProvider+Mapping.swift`).
- Layout → a sub-view or `ViewModifier` in its own file (`ChatView+Turns.swift`).
- Test suites → one `@Suite` per feature, fixtures in a shared protocol extension
  (`ChatProviderTestHelpers`, `HistoryPaginationFixtures`).

Stored state that sibling extensions mutate is module-internal rather than `private(set)`; keep
the declaration in the primary file with a `// MARK: State` header so the surface stays obvious.

### Localization catalog

`Sources/AIConversation/Resources/Localizable.xcstrings` must stay in Xcode's serialization
(sorted keys, two-space indent, `"key" : value`). Any other serializer rewrites every line, the
diff becomes unreviewable, and Xcode flips it back on the next edit. Either edit the catalog in
Xcode, or after a hand / scripted edit run:

```bash
./scripts/format-xcstrings.py Sources/AIConversation/Resources/Localizable.xcstrings
```

A PR touching the catalog should show only the added or changed keys. New keys need all 16 locales.

## Products

| Product | Contents |
|---------|----------|
| `AIConversation` | The chat UI and its public entry point, `AIChat` |

Two internal targets sit behind it: `AIConversationEngine` (conversation state, streaming, parsing)
and `AIConversationCore` (networking, token storage). Both use `package` access and are deliberately
absent from the product list — the public surface is `AIChat` alone.

## Strict Concurrency

The library and tests use Swift 6 language mode. Keep new API `Sendable`-safe. `AIChat` is
`@MainActor`; the conversation state lives in an actor behind it.

## License

By contributing, you agree that your contributions are licensed under the Apache License, Version 2.0.
