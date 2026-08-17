# Diverge SDK for iOS

Open-source ecommerce SDK for **iOS**, distributed via Swift Package Manager.

> Android SDK: [Diverge-SDK-Android](https://github.com/askdiverge/Diverge-SDK-Android)

## Requirements

| | Minimum | Notes |
|--|---------|-------|
| **Host app deployment target** | **iOS 15.0+** | Runtime OS floor for apps that embed the SDK |
| **Swift toolchain (to build the package)** | Swift 6 / `swift-tools-version: 6.0` | Language mode used by the package sources |
| **Contributor / CI Xcode** | Newest stable on `macos-26` (currently Xcode 26+) | Matches GitHub Actions; not a pin to an older Xcode |

Consumers can ship apps that support iOS 15 while building with a Swift 6–capable Xcode. The OS floor and the toolchain requirement are independent.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/askdiverge/Diverge-SDK-iOS.git", from: "0.1.1")
]
```

Add products `DivergeSDK` (required) and `DivergeSDKUI` (optional status UI). Prefer version pins — do not track `main`.

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

Push a SemVer tag (`v0.1.1`) for a GitHub Release / SPM version.

## License

[Apache-2.0](LICENSE.md) — Copyright © 2026 Diverge
