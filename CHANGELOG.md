# Changelog — Diverge SDK iOS

## [Unreleased]

> Livechat (human agent), in-conversation contact / support-ticket / custom forms, the livechat
> waiting form and CSAT, and the conversation rating overlay on close are **not** in this line.
> They live on the `iOS_CS_Livechat_Contact_Form` branch and are logged there.

### Fixed

- **`.system` appearance no longer freezes on the first-rendered scheme.** With a distinct
  `dark_theme`, `ChatView` used to write `preferredColorScheme` back into the very environment it
  read, so a live Dark Mode flip repainted nothing. Under `.system` with a distinct dark palette the
  chat now leaves chrome to the environment; host locks (`.light` / `.dark`) still pin it.
- **Link-mode add-to-cart honours `/config`.** A card carrying `add_to_cart.url` no longer shows
  a cart button on a chatbot whose dashboard has `product_card.add_to_cart.enabled` off.
- **Product grids keep one image ratio.** When any card in a grid offers cart, every card uses the
  squarer image so titles, prices and CTAs stay aligned across a mixed row.
- **Quick replies on older turns are gone, not greyed.** Only the newest bot turn renders its
  `quick_replies` chips (web parity); chips now visibly dim while a reply streams.
- **Banner CTA is reachable by identifier.** `banner.<id>` was applied to a bare stack, so SwiftUI
  pushed it onto the message text and the CTA, hiding `banner.cta.<id>`. The card is now a
  container element.
- **Composer send button** carries a localised "Send message" label and a `chat.send` identifier
  (it previously read as the SF Symbol name "Up"). Toolbar close / reset labels are localised
  (`chat.close`, `chat.reset`).

### Changed

- **Consumer follow-ups review:** Start prompts and quick replies share one outlined-chip wrap
  layout. Header close / reset glyphs paint `toolbarIcon` and optional `headerButtonBackground`.
  Failed send clears `lastSentUserTurnID` with the echo.
- **Multi-image send:** the composer keeps up to eight photos per message. Chip thumbnails
  are a separate ~170 px downsample (the wire payload stays 1024 px JPEG). `/config`
  `image_enabled` gates attach together with host `Configuration.attachments` (`.disabled`
  always wins; omitted `image_enabled` stays enabled for older APIs).
- String Catalog trimmed to the keys this line ships (`form.*`, `livechat.*`, `rating.*`,
  `sessionForm.*` removed; `rating.close` renamed `chat.close`). Legacy `/actions` attachment caps
  and the unused `OutgoingAttachment: Encodable` shape are removed — `/messages` parts are encoded
  by `SendMessageRequest`.

### Added

- **`X-Diverge-SDK-Version` request header.** Every authenticated API call (`/config`,
  `/messages`, `/export`, `/banners`, delete) now carries the SDK release from the generated
  `VersionInfo`, so the backend can log adoption and gate wire-contract changes per version.
  Attachment / font downloads stay header-less. Hosts need no change.
- **Stand-in UITest harness** in `Tests/Standin/` (10 XCUITest suites, Driver host, Python
  stand-in servers). `make uitest` drives Sample (Local) against each server. CI job `uitest`
  in `.github/workflows/ios.yml` runs after package tests. Suites share one `composer()` /
  `tapSend()` driver keyed on `chat.send`; the history stand-in supports `/__control` reset so
  both flows start from seed.
- **Shared card / grid chrome:** `CardGrid` owns the two-column `LazyVGrid` metrics used by
  product and suggestion layouts; `MediaCardBody` owns image + title + description (with optional
  image overlay and footer). Product/suggestion views compose those; start prompts and
  in-conversation quick replies stay on `OutlinedChipFlow`.
- **Public `/config` `image_enabled`:** the SDK hides photo attach when the chatbot's image
  flow is off. Host `Configuration.attachments == .disabled` still always wins; omitted
  `image_enabled` (older APIs) stays enabled.
- **Consumer follow-ups (SDK + API):** upload-prompt picks honour `accepted_types` /
  `max_size_bytes`; `Color(css:)` parses hex + `rgb()`/`rgba()` for theme/banner (optional header
  button fill); `Turn.system` muted centred rows (excluded from `lastBotTurnID`); topDown exchange
  arm uses `lastSentUserTurnID` (send echoes only — prepend no longer arms). Product cart: catalog
  metadata sku, widget-internal custom add-to-cart marker pattern, optional `ProductAddToCart.url`
  (link-mode opens URL; else host `onAddToCart`). In-conversation `quick_replies` part + chips on
  the latest bot turn (disabled while streaming).
- **In-chat banners:** sticky promo strips under the nav from visitor
  `GET /api/v1/chat/banners?url=`, using the same `contextProvider` page string as start prompts
  (schedule / URL / `is_default` stay on the server). Bootstrap-only; soft-fails to no strip on
  older APIs (404 / transport). A 401 surfaces the session-ended alert. Unknown `cta_style` and
  one malformed row do not drop the list. Blank messages are omitted. CTA opens via
  `openURL` / `onOpenLink` when both label and absolute http(s) URL exist;
  dismissible banners hide in-memory until a new `AIChat` / `makeView()`.
- **Download my data:** Privacy & Data gains a **Download my data** row that calls
  `GET /api/v1/chat/export` with the visitor bearer, writes the JSON body to a temp file, and opens
  the system share sheet. Export does **not** drop the token or clear the conversation (unlike
  delete, which remains the host `deleteData` hook). A 401 surfaces the session-ended alert; other
  failures show an inline error on the privacy sheet. The share sheet is nested on Privacy
  (not ChatView). Dismissing Privacy cancels an in-flight export. The JSON is one
  protected temp file, deleted after share or dismiss. iPad sets a popover source; macOS
  share is best-effort.
- **Dark appearance:** `/config`'s `dark_theme` is decoded alongside `theme`. The chat paints the
  active palette from the environment color scheme, with an optional host lock via
  `AIChat.Configuration.appearance` (`.system` default, or `.light` / `.dark`). `.dark` selects the
  `dark_theme` slot — it does not invent a dark look. When a chatbot has no dark theme configured
  the server clones light into `dark_theme`, so the chat stays visually light under `.system` (in
  Dark Mode) and under `.dark`. System chrome (keyboard, pickers) follows the **painted** palette,
  not the host lock alone. A broken dark hex degrades to that customer's light palette, not the SDK
  default. Mint a new `AIChat` to change `appearance` after the first `makeView()`.
- Product card CTAs: each card shows a themed open-product capsule (dashboard `product_card.open_label`,
  or localised "View product" when null) and opens `ProductCard.url` via `openURL` / `onOpenLink`.
  When `/config` enables add-to-cart, a sibling "Add to cart" button appears on cards that carry a
  sku and either a link-mode cart URL (opened via `openURL` / `onOpenLink`) or — when the host sets
  `AIChat.Configuration.onAddToCart` — reports `AIChat.ProductSelection` (id, sku from
  `{{add_to_cart:SKU}}`, title, url). Splash badges render on the image; `theme.product_card.button`
  colours the CTA when present. One malformed product no longer aborts the SSE stream (history /
  `done` **and** live `append_product` deltas).
- Close button: when the host sets `AIChat.Configuration.onClose`, the SDK shows a toolbar close
  control that calls it; absent, the host owns dismissal exclusively.
- The conversational chat SDK: `AIChat`, `AIChat.Configuration` and `ConversationFlow` as the entire
  public surface, with `makeView()` for SwiftUI and `makeViewController()` for UIKit
- Host-owned hooks for session tokens, conversation reset and data deletion; optional per-message
  context, in-message link routing, and a choice of conversation layout
- Localization across 16 languages via a String Catalog
- Remote font loading, registered from a content-hash-keyed on-disk cache that holds one font
- Suggestion cards: the `suggestions` message part (authoritative and streamed) renders as a
  two-column grid of VoiceOver-activatable cards; tapping one sends its `prompt_text` as the next
  user message. Cards are disabled while a reply is streaming; empty card parts render nothing and a
  malformed `image_url` no longer aborts the stream
- Assistant image and file parts render in the conversation — from history and live via the
  terminal `done` event, which the provider now reconciles the finished turn from; tapping opens
  the attachment through `openURL` / `onOpenLink`. Failed loads and expired signed URLs
  (`url_expires_at`) show a disabled "unavailable" tile instead of a blank box — flipping live the
  moment the TTL passes while on screen — and host-less attachment paths resolve against
  `apiBaseURL`
- The conversation-bound `visitor_token` the API returns on `done` is adopted for subsequent
  turns, so multi-turn chats stay on one thread as the Chatbot API contract asks. Falls back to
  the host's `tokenProvider` if the adopted token is later rejected
- Visitors can attach a photo to a message. The composer's attach control opens the system
  `PhotosPicker` (out-of-process, so no photo-library permission prompt); the pick is downsampled
  to 1024 px and re-encoded as JPEG on device — which drops the photo's metadata (GPS location,
  capture time, device make / model; only pixel dimensions remain) —
  and shown as a removable chip until sent. Sent photos render in the user pane, live and from
  history. Up to eight photos per message. `AIChat.Configuration.attachments` (default
  `.photoLibrary`) lets a host pass `.disabled`; `/config` `image_enabled: false` also hides
  attach. No Info.plist usage string is
  needed; the SDK's privacy manifest now declares "Photos or Videos" as collected, so hosts should
  mirror that in their App Privacy answers — see `Docs/integration/v0.1.0.md`
- `AIChat.Configuration.apiBaseURL` (default `DivergeAPI.productionBaseURL`) so hosts can point the
  SDK at a non-production Chatbot API while integrating. The Sample app selects the host per build
  configuration via `Samples/iOS/Config/*.xcconfig`, and `scripts/mint-visitor-token.sh` mints a
  visitor JWT against the same host
- Older history loads on scroll-up. Within one viewport of the top the SDK fetches the next
  history page (a "Loading earlier messages" spinner overlays the top edge while it does) and keeps
  the visitor exactly where they were once the page has laid out, in all three layouts. A failed
  load never scrolls; it shows a "Couldn't load older messages · Retry" bar at the top edge instead
  of a passing notice, and scrolling again after the failure retries as well
- The `request_image_upload` marker renders as an in-conversation card ("Add a photo so I can help
  you further" + an "Add photo" button). Tapping it opens the same `PhotosPicker` as the composer
  attach control; the pick lands as a pending chip and sends through the existing image path.
  When `AIChat.Configuration.attachments` is `.disabled` the marker is dropped at ingestion, so a
  marker-only assistant message leaves no empty row; the card and the composer attach button share
  one enable rule and are disabled together while a photo encodes or a reply streams. No decline button — the marker is a real history part and would reappear on
  relaunch. Copy is SDK-owned (the API supplies none)
- Start-prompt chips from `GET /api/v1/chat/config` (`start_prompts`). Outlined capsules render
  below the welcome turn before the visitor has sent a message; tapping one sends `prompt_text`
  through the same path as suggestion cards. Clients filter by `url_pattern` against the host
  `contextProvider` string at each `makeView()` bootstrap (literal substring; null-pattern prompts
  are globals when nothing matches). Hosts that configured dashboard URL patterns should include a
  path or URL in `contextProvider` (e.g. `/products` or `https://shop.example.com/products/123`), not
  only a SKU blurb. Long labels wrap; duplicate `prompt_text` rows stay distinct by index. Chips
  hide after the first user turn and while a reply streams; reset brings them back. The SDK does not
  strip stored `{{quick_replies:…}}` in history — that is the API converter.

### Changed (public surface)

- **Breaking:** the previous public API is gone — `Diverge`, `DivergeConfiguration`, `DivergeClient`,
  `DivergeError`, `Environment`, and the `DivergeSDKUI` product with `DivergeStatusView`
- Single product `AIConversation`, replacing the core/UI product split. The engine and networking
  targets are internal
- No third-party dependencies: DocC is built with `xcodebuild docbuild` instead of `swift-docc-plugin`
- Swift 6 language mode is set once at package level
- Minimum macOS raised to **15.0** (iOS floor unchanged at 18.0)
- Conversation state is one chronological list of turns. History pages whose roles do not
  strictly alternate (bot-led older pages, consecutive bots or users, system notes) render in
  the order the API sent them — the previous two-pane zip by index no longer re-pairs them.
  A history page landing while a reply streams leaves the in-flight turn and the echo in place,
  and a failed send removes exactly those two turns. In the top-down flow the buffer under a
  lifted user turn is sized from every turn beneath it, not just the last bot turn

### Removed

- The SwiftFormat gate from CI, the Makefile and local CI
- `Package.resolved`, which no longer has dependencies to pin

## [0.1.0] - 2026-08-13

### Added

- Public API: `Configuration`, `Environment`, `DivergeClient`, `Diverge.configure` / `shared`
- `DivergeSDKUI` product with `DivergeStatusView`
- Swift 6; DocC; SemVer GitHub Releases
- `Docs/privacy/`, `Docs/ops/`, `Docs/accessibility/` runbooks and checklists
- Per-release integration template under `Docs/integration/TEMPLATE.md`

### Changed

- Apache License 2.0
- Minimum iOS **18.0**
- CI on `macos-26` with newest Xcode
- Split out of the former monorepo into this dedicated iOS repository
- Docs and CONTRIBUTING are iOS-only (removed monorepo / Android leftovers)
- A11y tests use accessibility **contract** string dumps (not pixel snapshots)
- Public site links use absolute GitHub URLs so they resolve on GitHub Pages
- README clarifies host **deployment target** (iOS 18) vs **Swift 6 toolchain** to build the package
