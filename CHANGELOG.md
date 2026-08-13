# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-13

### Added

- Public API: `Configuration`, `Environment`, `DivergeClient`, `Diverge.configure` / `shared`
- `DivergeStatusView` (SwiftUI) in separate `DivergeSDKUI` product
- Swift 6 language mode; accessibility dump contract tests
- DocC for `DivergeSDK` + `DivergeSDKUI`; docs site assembly
- Repository scaffold: SPM package, sample, CI workflows
- SemVer GitHub Releases via `v*` tags

### Changed

- Relicensed to Apache License, Version 2.0
- Minimum iOS deployment target **18.0**
- CI on `macos-26` with newest installed Xcode (not pinned to 16.4)
- Extracted from the former monorepo into a dedicated iOS repository
