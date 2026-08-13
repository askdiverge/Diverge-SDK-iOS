# Diverge SDK for iOS

Open-source ecommerce SDK for **iOS**, distributed via Swift Package Manager.

> Platform SDKs live in separate repositories. Android: [Diverge-SDK-Android](https://github.com/DialogIntelligens/Diverge-SDK-Android). Overview hub: [Diverge-SDK](https://github.com/DialogIntelligens/Diverge-SDK).

Configure with a sandbox or production API key, then use the shared client for environment and version introspection.

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS | 18.0+ |
| Swift | 6.0 language mode (Xcode 26+) |
| Xcode | 26+ |

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/DialogIntelligens/Diverge-SDK-iOS.git", from: "0.1.0")
]
```

Add products `DivergeSDK` (required) and `DivergeSDKUI` (optional status UI).

```swift
import DivergeSDK
import DivergeSDKUI

try Diverge.configure(
    Configuration(apiKey: "sk_sandbox_demo", environment: .sandbox)
)
let client = try Diverge.shared
DivergeStatusView(client: client)
```

Publish = push a SemVer Git tag (`v0.1.0`); consumers resolve from GitHub via SPM. Prefer version pins — do not track `main`.

## Versioning and channels

Single source of truth: the root [`VERSION`](VERSION) file. After changing it, run:

```bash
./scripts/sync-version.sh
./scripts/check-version.sh
```

| Channel | Git tag example | GitHub Release |
|---------|-----------------|----------------|
| Stable | `v1.2.3` | Latest release |
| Beta | `v1.2.3-beta.1` | Prerelease |
| Canary | `v1.2.3-canary.1` | Prerelease |

## Documentation

- Getting started / ATT: [`Docs/site/`](Docs/site/)
- Integration baseline: [`Docs/integration/v0.1.0.md`](Docs/integration/v0.1.0.md)

## Samples

[`Samples/iOS`](Samples/iOS) — links `DivergeSDK` + `DivergeSDKUI`

## Concurrency

Swift 6 language mode. `Diverge.configure` / `shared` are lock-synchronized. Prefer `@_spi(Testing) Diverge.reset()` only from tests.

## Make targets

```bash
make help
make ios-test
make docs-docc
```

## License

[Apache-2.0](LICENSE.md) — Copyright © 2026 Diverge
