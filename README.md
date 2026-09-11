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
credentials, it calls back to the host for them. **Download my data** (Privacy & Data) is SDK-owned:
it calls `GET /api/v1/chat/export` with the visitor bearer and opens the share sheet; it does not
use a host hook. The JSON is written to one protected temp file and deleted when the visitor
dismisses Privacy or finishes sharing. Delete remains the host `deleteData` callback
(typically `DELETE /api/v1/chat`).

**`contextProvider`** — used in three places, from the same hook:

1. **Send-time AI context** — resolved on every send so the assistant can answer against the current
   screen (SKU, category, screen name).
2. **Start-prompt matching** — awaited once at each `makeView()` bootstrap and matched as a
   **literal substring** against dashboard `url_pattern`s. If any pattern matches, only those chips
   show; otherwise global (null-pattern) prompts remain. A SKU blurb like
   `"PDP · Rieker Men's shoes 13510-00 black"` will not match `/products`. Include a path or URL
   when patterned chips should appear.
3. **In-chat banners** — the same bootstrap page string is sent as `url` on
   `GET /api/v1/chat/banners`. The server applies schedule, substring match, and `is_default`
   fallback (same rules as the web widget). Soft-fails if the route is missing (404 / transport).
   A 401 ends the session (same alert as send / export).

Matching / banner fetch do not re-run while the same `ChatView` stays on screen. Presenting again
(`makeView()`) bootstraps a new view model and re-filters.

```swift
contextProvider: {
    // Path/URL so dashboard url_patterns like "/products" can match.
    await currentScreen.pageURL  // "https://shop.example.com/products/123" or "/products"
}
```

**`onOpenLink`** — links inside a reply. Left `nil`, the SDK falls back to the system action: the URL
opens in the browser and the user leaves your app. Set it to keep them in-app and route the URL
through your own deep-link handling.

```swift
onOpenLink: { url in deepLinkRouter.handle(url) }
```

**`onAddToCart`** — product-card "Add to cart" taps. The button only appears when this is set,
`GET /config` reports `product_card.add_to_cart.enabled`, **and** the card carries a sku.
The callback receives `AIChat.ProductSelection`: `id` is the product identifier (a catalog id
when the source supplies one, otherwise a parser-derived stand-in), `sku` is the commerce
SKU from a `{{add_to_cart:SKU}}` marker (or JSON field), plus `title` and `url`. Treat `sku`
as untrusted input and validate it against your catalog before calling a cart API. The SDK
does not show "added" feedback — the host owns toasts / cart UI. Absent → no cart button;
open-product still works via `openURL` / `onOpenLink`.

**`onClose`** — when set, the SDK shows a close button that calls `onClose` so the host can tear
down the chat UI. (Conversation rating and livechat live on the
`iOS_CS_Livechat_Contact_Form` branch.)

**`attachments`** — `.photoLibrary` (default) shows a photo-library picker (up to eight photos per
message). `/config` `image_enabled: false` hides attach even when this is `.photoLibrary`.
`.disabled` always wins. Omitted `image_enabled` on older APIs is treated as enabled.

**`appearance`** — which `/config` palette slot the chat paints (`theme` / `dark_theme`). Defaults
to `.system` (follow the environment color scheme). Pass `.light` or `.dark` to lock the slot.
`.dark` means “use `dark_theme`”, not “invent a dark look”: when a chatbot has no dark theme the
server clones light into `dark_theme`, so the chat stays visually light under `.system` in Dark
Mode and under `.dark`. Keyboard and pickers follow the painted palette (a cloned theme does not
force a dark keyboard). Captured on the first `makeView()` — mint a new `AIChat` to change it.

```swift
appearance: .system  // or .light / .dark
```

```swift
onAddToCart: { selection in cart.add(sku: selection.sku, productURL: selection.url) }
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
