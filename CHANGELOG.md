# Changelog — Diverge SDK iOS

## [Unreleased]

### Added

- The conversational chat SDK: `AIChat`, `AIChat.Configuration` and `ConversationFlow` as the entire
  public surface, with `makeView()` for SwiftUI and `makeViewController()` for UIKit
- Host-owned hooks for session tokens, conversation reset and data deletion; optional per-message
  context, in-message link routing, and a choice of conversation layout
- Localization across 16 languages via a String Catalog
- Remote font loading, registered from a content-hash-keyed on-disk cache that holds one font

### Changed

- **Breaking:** the previous public API is gone — `Diverge`, `DivergeConfiguration`, `DivergeClient`,
  `DivergeError`, `Environment`, and the `DivergeSDKUI` product with `DivergeStatusView`
- Single product `AIConversation`, replacing the core/UI product split. The engine and networking
  targets are internal
- No third-party dependencies: DocC is built with `xcodebuild docbuild` instead of `swift-docc-plugin`
- Swift 6 language mode is set once at package level
- Minimum macOS raised to **15.0** (iOS floor unchanged at 18.0)

### Removed

- The SwiftFormat gate from CI, the Makefile and local CI
- `Package.resolved`, which no longer has dependencies to pin

## [0.1.0] - 2026-08-13

### Added

- Public API: `Configuration`, `Environment`, `DivergeClient`, `Diverge.configure` / `shared`
- `DivergeSDKUI` product with `DivergeStatusView`
- Swift 6; DocC; SemVer GitHub Releases
- `Docs/privacy/`, `Docs/ops/`, `Docs/accessibility/` runbooks and checklists
- Per-release integration template under `Docs/integration/TEMPLATE.md`

### Changed

- Apache License 2.0
- Minimum iOS **18.0**
- CI on `macos-26` with newest Xcode
- Split out of the former monorepo into this dedicated iOS repository
- Docs and CONTRIBUTING are iOS-only (removed monorepo / Android leftovers)
- A11y tests use accessibility **contract** string dumps (not pixel snapshots)
- Public site links use absolute GitHub URLs so they resolve on GitHub Pages
- README clarifies host **deployment target** (iOS 18) vs **Swift 6 toolchain** to build the package
