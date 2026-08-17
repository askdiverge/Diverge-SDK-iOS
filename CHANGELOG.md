# Changelog — Diverge SDK iOS

## [Unreleased]

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
