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

Add the **`AIConversation`** product. Prefer SemVer pins / the `v0.1.0` GitHub Release — do not track `main`.

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

Push a SemVer tag (`v0.1.0`) for a GitHub Release / SPM version. Keep `0.1.0` until the API is stable; then bump for breaking or feature releases.

## License

[Apache-2.0](LICENSE.md) — Copyright © 2026 Diverge
