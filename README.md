# Diverge SDK for iOS

Open-source ecommerce SDK for **iOS**, distributed via Swift Package Manager.

> Android SDK: [Diverge-SDK-Android](https://github.com/mohamedaldahoul/Diverge-SDK-Android) · Hub: [Diverge-SDK](https://github.com/DialogIntelligens/Diverge-SDK)

## Requirements

| Platform | Minimum |
|----------|---------|
| iOS | 18.0+ |
| Swift | 6.0 language mode (Xcode 26+) |
| Xcode | 26+ |

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mohamedaldahoul/Diverge-SDK-iOS.git", from: "0.1.0")
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

Push a SemVer tag (`v0.1.0`) for a GitHub Release / SPM version.

## License

[Apache-2.0](LICENSE.md) — Copyright © 2026 Diverge
