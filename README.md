# Diverge SDK for iOS

Open-source ecommerce SDK for **iOS**, distributed via Swift Package Manager.

> Android SDK: [Diverge-SDK-Android](https://github.com/askdiverge/Diverge-SDK-Android)

## Requirements

| | Minimum | Notes |
|--|---------|-------|
| **Host app deployment target** | **iOS 18.0+** | Runtime OS floor for apps that embed the SDK |
| **Swift toolchain (to build the package)** | Swift 6 / `swift-tools-version: 6.0` | Language mode used by the package sources |
| **Contributor / CI Xcode** | Newest stable on `macos-26` (currently Xcode 26+) | Matches GitHub Actions; not a pin to an older Xcode |

The OS deployment floor and the Swift toolchain requirement are independent. Version stays at **0.1.0** until the public API is stable.

## Installation

In Xcode: **File → Add Package Dependencies…** → paste  
`https://github.com/askdiverge/Diverge-SDK-iOS.git` → version **0.1.0** (Up to Next Major).

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/askdiverge/Diverge-SDK-iOS.git", from: "0.1.0")
]
```

Add products **`DivergeSDK`** (required) and **`DivergeSDKUI`** (optional status UI). Prefer SemVer pins / the `v0.1.0` GitHub Release — do not track `main`.

```swift
import DivergeSDK
import DivergeSDKUI

try Diverge.configure(
    Configuration(apiKey: "sk_sandbox_demo", environment: .sandbox)
)
let client = try Diverge.shared
DivergeStatusView(client: client)
```

## Versioning

Root [`VERSION`](VERSION). After changing it:

```bash
./scripts/sync-version.sh
./scripts/check-version.sh
```

Push a SemVer tag (`v0.1.0`) for a GitHub Release / SPM version. Keep `0.1.0` until the API is stable; then bump for breaking or feature releases.

## License

[Apache-2.0](LICENSE.md) — Copyright © 2026 Diverge
