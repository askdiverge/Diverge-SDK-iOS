# Changelog — Diverge SDK iOS

## [Unreleased]

## [0.1.1] - 2026-08-17

### Changed

- Minimum iOS **15.0** (was 18.0)
- Status / sample UI uses iOS 15-compatible SwiftUI APIs (`foregroundColor`, `PreviewProvider`)
- Docs and CONTRIBUTING are iOS-only (removed monorepo / Android leftovers)
- A11y tests renamed to accessibility **contract** tests (string dumps, not pixel snapshots)
- Public site links use absolute GitHub URLs so they resolve on GitHub Pages
- README clarifies host **deployment target** (iOS 15) vs **Swift 6 toolchain** to build the package

### Added

- `Docs/privacy/`, `Docs/ops/`, `Docs/accessibility/` runbooks and checklists
- Per-release integration template under `Docs/integration/TEMPLATE.md`

## [0.1.0] - 2026-08-13

### Added

- Public API: `Configuration`, `Environment`, `DivergeClient`, `Diverge.configure` / `shared`
- `DivergeSDKUI` product with `DivergeStatusView`
- Swift 6; DocC; SemVer GitHub Releases

### Changed

- Apache License 2.0
- Minimum iOS **18.0** (superseded in 0.1.1)
- CI on `macos-26` with newest Xcode
- Split out of the former monorepo into this dedicated iOS repository
