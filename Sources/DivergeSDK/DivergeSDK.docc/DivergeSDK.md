# ``DivergeSDK``

An ecommerce SDK for integrating Diverge experiences into iOS apps.

## Overview

Configure the SDK once at launch with an API key and environment, then use the shared client.

```swift
import DivergeSDK

try Diverge.configure(
    Configuration(apiKey: "sk_sandbox_...", environment: .sandbox)
)
let client = try Diverge.shared
print(client.apiBaseURL)
```

For status UI, also link the `DivergeSDKUI` product and use `DivergeStatusView`.

### Threading

`Diverge.configure` and `Diverge.shared` are synchronized with a lock. Call `configure` once at launch; prefer reading `shared` from any queue after that.

### Environments

| Case | Raw value | API base URL |
|------|-----------|--------------|
| ``Environment/sandbox`` | `sandbox` | `https://sandbox.api.askdiverge.ai` |
| ``Environment/production`` | `production` | `https://api.askdiverge.ai` |

Android mirrors these with `Environment.SANDBOX` / `PRODUCTION` and `wireName`.

## Topics

### Essentials

- ``Diverge``
- ``Configuration``
- ``Environment``
- ``DivergeClient``
- ``DivergeError``

### Related

Status UI ships in the separate SPM product `DivergeSDKUI` (`DivergeStatusView`).
