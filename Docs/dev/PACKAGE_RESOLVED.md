# Why `Package.resolved` is committed

This iOS repository commits `Package.resolved` so DocC plugin and CI resolve the same dependency graph across machines and GitHub Actions runners.

- Do not delete `Package.resolved` when bumping tools; update it via `swift package resolve` / Xcode and commit the diff.
- Consumers of the SDK as an SPM dependency get their own resolution; this file mainly stabilizes **this** repo’s DocC + CI builds.
