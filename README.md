# Diverge SDK for iOS

Open-source ecommerce SDK for **iOS**, distributed via Swift Package Manager.

> Android SDK: [Diverge-SDK-Android](https://github.com/askdiverge/Diverge-SDK-Android)

## Requirements

| | Minimum | Notes |
|--|---------|-------|
| **Host app deployment target** | **iOS 18.0+** | Runtime OS floor for apps that embed the SDK |
| **Swift toolchain (to build the package)** | Swift 6 / `swift-tools-version: 6.0` | Language mode used by the package sources |
| **Contributor / CI Xcode** | Newest stable on `macos-26` (currently Xcode 26+) | Matches GitHub Actions; not a pin to an older Xcode |

The OS deployment floor and the Swift toolchain requirement are independent. Releases follow SemVer: `1.x.y` keeps the public API and wire contract stable; patch versions fix, minor versions add, a major version is the only place a breaking change may land.

## Installation

In Xcode: **File → Add Package Dependencies…** → paste  
`https://github.com/askdiverge/Diverge-SDK-iOS.git` → version **1.0.0** (Up to Next Major).

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/askdiverge/Diverge-SDK-iOS.git", from: "1.0.0")
]
```

Add the **`AIConversation`** product. Prefer SemVer pins / the `v1.0.0` GitHub Release — do not track `main`.

## Usage

The SDK renders the conversation and nothing else — the host supplies the session token and data
lifecycle, and owns how the chat is presented and dismissed.

```swift
import AIConversation

let chat = AIChat(
    .init(
        tokenProvider: { try await myAuth.sessionToken() },
        resetConversation: { try await myAuth.newSessionToken() },
        deleteData: { try await myAuth.deleteVisitorData() }
    )
)

// SwiftUI
chat.makeView()

// UIKit
present(chat.makeViewController(), animated: true)
```

You don't have to store the `AIChat` instance unless you explicitly want the session to outlive the
presentation lifecycle.

## Configuration

`tokenProvider`, `resetConversation` and `deleteData` are required — the SDK never mints or stores
credentials, it calls back to the host for them.

**`contextProvider`** — resolved on every send, so the assistant can answer against what the user is
actually looking at rather than the message alone. Return whatever describes the current screen: the
product being viewed, the category being browsed, the order being queried.

```swift
contextProvider: { await currentScreen.assistantContext }  // "PDP · Rieker Men's shoes 13510-00 black"
```

**`onOpenLink`** — links inside a reply. Left `nil`, the SDK falls back to the system action: the URL
opens in the browser and the user leaves your app. Set it to keep them in-app and route the URL
through your own deep-link handling.

```swift
onOpenLink: { url in deepLinkRouter.handle(url) }
```

**`conversationFlow`** — how arriving turns are laid out.

| | |
|--|--|
| `.topDown` (default) | On send, the user's message lifts to the top of the screen and the reply streams into the space reserved beneath it. |
| `.bottomUp` | Classic chat: new turns land at the bottom and the list follows the newest message. |

**`environment`** — which Diverge backend the SDK talks to. Defaults to `.production`; a host that
says nothing keeps talking to the live API. Use `.development` to integrate against backend changes
before they are released. The SDK owns the URLs for both.

```swift
environment: .development
```

## Shared and per-instance configuration

The two are not exclusive. Register a shared configuration once at launch and mint instances from it
anywhere:

```swift
AIChat.configure(.init(tokenProvider: …, resetConversation: …, deleteData: …))
let chat = AIChat()
```

A shared configuration suits a single app-wide chat. Passing a configuration directly suits chats
scoped to one screen, where the context or link routing differs per entry point. Both can coexist in
the same app.

## Versioning

Root [`VERSION`](VERSION). After changing it:

```bash
./scripts/sync-version.sh
./scripts/check-version.sh
```

Push a SemVer tag (`v1.0.0`) for a GitHub Release / SPM version. Patch for fixes (`1.0.1`), minor for additive features (`1.1.0`), major for a breaking public-API or wire-contract change (`2.0.0`). The SDK sends its version to the backend on every call, so the tag and `VERSION` must agree.

## License

[Apache-2.0](LICENSE.md) — Copyright © 2026 Diverge
