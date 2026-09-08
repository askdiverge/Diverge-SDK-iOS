# Changelog — Diverge SDK iOS

## [Unreleased]

### Changed

- **Reset forgets submitted forms:** a **successful** `ChatView.ViewModel.reset()` now calls
  `SubmittedFormStore.removeAll()` as well as dropping in-memory drafts. A failed reset leaves
  the conversation (and those part ids) intact. A new conversation cannot re-open a lead/ticket
  already filed on the previous one from this device.
- **Consumer follow-ups review:** 422 `params` last-wins on duplicate field keys; unmatched
  keys join the envelope message on the card `formError`. Start prompts and quick replies
  share one outlined-chip wrap layout. Header close / reset / livechat glyphs paint
  `toolbarIcon` and optional `headerButtonBackground`. Failed send / livechat pop clears
  `lastSentUserTurnID` with the echo.
- **Multi-image send:** the composer keeps up to eight photos per message. Chip thumbnails
  are a separate ~170 px downsample (the wire payload stays 1024 px JPEG). `/config`
  `image_enabled` gates attach together with host `Configuration.attachments` (`.disabled`
  always wins; omitted `image_enabled` stays enabled for older APIs).

### Added

- **Stand-in UITest harness** in `Tests/Standin/` (13 XCUITest suites, Driver host, Python
  stand-in servers). `make uitest` drives Sample (Local) against each server. CI job `uitest`
  in `.github/workflows/ios.yml` runs after package tests.
- **Shared card / grid chrome:** `CardGrid` owns the two-column `LazyVGrid` metrics used by
  product and suggestion layouts; `MediaCardBody` owns image + title + description (with optional
  image overlay and footer). Product/suggestion views compose those; start prompts and
  in-conversation quick replies stay on `OutlinedChipFlow`.
- **Public `/config` `image_enabled`:** the SDK hides photo attach when the chatbot's image
  flow is off. Host `Configuration.attachments == .disabled` still always wins; omitted
  `image_enabled` (older APIs) stays enabled.
- **Consumer follow-ups (SDK + API):** form **422** `ApiError.params` map onto per-field errors
  (waiting-form Save included); upload-prompt picks honour `accepted_types` / `max_size_bytes`;
  `Color(css:)` parses hex + `rgb()`/`rgba()` for theme/banner (optional header button fill);
  `Turn.system` muted centred rows (excluded from `lastBotTurnID`); topDown exchange arm uses
  `lastSentUserTurnID` (send echoes only — prepend no longer arms). Product cart: catalog
  metadata sku, widget-internal custom add-to-cart marker pattern, optional `ProductAddToCart.url`
  (link-mode opens URL; else host `onAddToCart`). In-conversation `quick_replies` part + chips on
  the latest bot turn (disabled while streaming).
- **Livechat host session callback:** optional `AIChat.Configuration.onLivechatSessionChange`
  delivers `AIChat.LivechatSessionInfo` (status + active agent name) when status or agent name
  changes — not on typing ticks or new messages. Hosts can badge or re-present from the last
  value. The poller still **parks** when `ChatView` is dismissed or the app backgrounds;
  dismissed polling is not offered (agent join/close while off-screen is only seen after
  re-present catch-up).
- **Livechat `client_context` + `state_version`:** `POST /livechat/handover` now
  sends an optional native `client_context` (OS, host app name/version mapped onto
  `browser` / `browser_version`, UI language, truncated page URL from
  `contextProvider`). Agents can see it while the visitor waits. The livechat
  poller decodes optional `state_version` and drops out-of-order GETs when both the
  incoming and last applied versions are present and the incoming value is
  strictly older — **before** fetching `/messages`, so a discarded tick cannot
  advance the message cursor. Missing versions always apply. The version watermark resets
  whenever the session generation bumps (handover / close / teardown / bootstrap).
  Form `start_livechat` still never POSTs handover.
- **Livechat send attachments + form `start_livechat`:** while an agent session is
  `active` and `/config` `livechat.attachments_enabled` is true, the composer attach
  control stays available (host `Configuration.attachments == .disabled` still wins).
  Pending chips are kept on agent join when attachments are enabled so a photo picked
  while waiting can be sent to the agent; otherwise they are dropped with the existing
  notice. Encode budget follows `max_attachment_size_bytes` when tighter than the default
  chat cap — including photos picked **while waiting** if `attachments_enabled` (those chips
  may be sent to the agent). The default 5 MiB livechat budget does not rewrite the chat cap.
  Custom in-thread forms whose server `submit_actions` include `start_livechat`
  return `livechat_session` on `POST /actions` — the SDK starts the poller from that
  signal and **does not** call `POST /livechat/handover`. If `GET /state` does not land
  waiting/active, confirmation stays and the send-failed notice is shown (401 still uses
  the session-ended alert). Contact / ticket forms without
  a session stay confirmation-only.
- **Livechat waiting form:** while livechat status is `waiting` and `/config` lists a form with
  `trigger == livechat_waiting`, the SDK loads `GET /forms/{id}` + `GET /session` once and shows an
  “Add details for the agent” card (newest-edge **footer** in both conversation flows, same slot as
  start prompts). `file` fields are omitted (`PATCH …/values` is string-only; no PhotosPicker). Save
  chrome sits above the composer so field order can match web (title → description → fields → error)
  without putting Save first. Save calls `PATCH /forms/{id}/values` with the visitor bearer (field
  keys kept camelCase); the visitor stays in the queue and can keep talking to the AI. Success keeps
  the fields filled with a “Details saved” caption (does not collapse like in-thread forms). Soft-fails
  fetch (404 / transport) with no card; **401** → session-ended; **409** (no longer waiting) hides
  the card; **422** field errors come from `ApiError.params` when present. Does **not**
  call `POST /actions`, `start_livechat`, or conversation rating. No Skip/dismiss on the form.
- **Livechat CSAT after close:** when a livechat session is `closed` and
  `GET /livechat/state` reports `feedback.status == pending` (closed edge, bootstrap of an
  already-closed session, or Chat Close last chance), the chat presents the same 1–5 rating
  overlay used for conversation close. Submit (and feedback-step Skip) call
  `POST /api/v1/chat/livechat/feedback` with the visitor bearer; scale Skip / backdrop
  dismiss the overlay without POSTing. The chat **stays open** — this path never calls
  `onClose`, never marks `RatingSession`, and never falls through to conversation
  `POST /rate`. Chat Close while the overlay is visible skips it (no POST) then calls
  `onClose`. A new waiting/active session dismisses a leftover overlay without POSTing.
  `Configuration.rating` gates conversation `/rate` only — CSAT follows server `feedback.pending`.
  After visitor Leave, a failed follow-up GET is retried once; if both fail the SDK publishes
  closed + pending rather than inventing `not_available`. A 401 surfaces the session-ended
  alert; **409** is treated as success. `shouldOfferRating` stays false while livechat is
  waiting/active or after `status == closed`.
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
- **Livechat / human agent (core loop):** when `/config` enables livechat, visitors can request a
  person from the toolbar (when `show_livechat_logo`) or a `request_human_agent` marker card.
  While **waiting**, messages still go to the AI (`POST /messages`); once **active**, sends route
  to `POST /livechat/messages`. A poller (2 s waiting / 3 s active, exponential backoff to 30 s)
  mirrors state, agent turns, and agent typing. Polling pauses when the chat is off-screen **or**
  the app leaves the foreground. The actor owns stop conditions (closed, inactive after a session,
  reset/delete, owner teardown, 401) and fetches remaining messages on the closed edge so the agent's
  last line is not dropped. Session-local notes mark queue entry, agent join, and end. HTTP **409**
  is distinguished as conflict (offline handover, or AI send racing an activated session — the
  latter starts the poller and re-routes) or livechat-inactive (session closed between polls — refresh
  then send on the AI path). Poller 401 surfaces the existing session-ended alert. Queue and
  agent UI are SDK-owned; optional ``onLivechatSessionChange`` reports last-known status for
  host badges. Post-session CSAT uses `POST /livechat/feedback` (see above).
  Polling while the sheet is dismissed stays parked (host callback, not a dismissed cadence).
  Sending attachments during livechat and form `start_livechat` are shipped (see
  Unreleased “Livechat send attachments”). `client_context` and `state_version`
  ordering are shipped (see Unreleased “Livechat `client_context` + `state_version`”).
  `onLivechatSessionChange` is shipped (see Unreleased “Livechat host session callback”).
- Product card CTAs: each card shows a themed open-product capsule (dashboard `product_card.open_label`,
  or localised "View product" when null) and opens `ProductCard.url` via `openURL` / `onOpenLink`.
  When `/config` enables add-to-cart **and** the host sets `AIChat.Configuration.onAddToCart`, a
  sibling "Add to cart" button appears on cards that carry a sku and reports
  `AIChat.ProductSelection` (id, sku from `{{add_to_cart:SKU}}`, title, url). Splash badges render
  on the image; `theme.product_card.button` colours the CTA when present. One malformed product
  no longer aborts the SSE stream (history / `done` **and** live `append_product` deltas).
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
- In-conversation contact, support-ticket and custom forms (`show_contact_form` /
  `show_support_ticket` / `show_form`). Field definitions travel inline on the marker; the SDK
  renders text / email / tel / textarea / dropdown / file inputs (plus ticket attachments), honours
  `visible_when` and `min_filled_fields`, and submits via `POST /api/v1/chat/actions`. Only the
  newest bot turn's forms are fillable — older ones render read-only because the server rejects
  their `part_id`. A successful submit collapses the card in place to a checkmark plus the
  server's `confirmation_text` (or SDK default copy), and the submission is remembered locally by
  `part_id` so a relaunch shows the confirmation instead of an editable form. Older forms show a
  visible "can no longer be edited" caption. `visible_when` follows the server's ordered evaluation
  (hiding a parent hides its dependents). File fields follow the host attachments gate. A keyboard
  "Done" bar and drag-to-dismiss keep the card's own controls reachable while typing. Dictionary
  field keys are encoded verbatim (no snake_case rewrite)
- Start-prompt chips from `GET /api/v1/chat/config` (`start_prompts`). Outlined capsules render
  below the welcome turn before the visitor has sent a message; tapping one sends `prompt_text`
  through the same path as suggestion cards. Clients filter by `url_pattern` against the host
  `contextProvider` string at each `makeView()` bootstrap (literal substring; null-pattern prompts
  are globals when nothing matches). Hosts that configured dashboard URL patterns should include a
  path or URL in `contextProvider` (e.g. `/products` or `https://shop.example.com/products/123`), not
  only a SKU blurb. Long labels wrap; duplicate `prompt_text` rows stay distinct by index. Chips
  hide after the first user turn and while a reply streams; reset brings them back. The SDK does not
  strip stored `{{quick_replies:…}}` in history — that is the API converter.
- Conversation rating on close. When the host sets `AIChat.Configuration.onClose`, the SDK shows a
  close button; tapping it presents a 1–5 numbered scale (web parity) when the conversation has a
  user turn and has not been rated yet. The prompt is an overlay card, not a nested sheet — a
  nested `.sheet` never surfaces when the host already presents `ChatView` in a sheet (Sample's
  pattern). Scores 1–3 open an optional free-text feedback step; 4–5 submit immediately via
  `POST /api/v1/chat/rate`. Scale Skip and a backdrop tap dismiss without POSTing; Skip on the
  feedback step still POSTs the numeric score with no written text, then calls `onClose`.
  `AIChat.Configuration.rating` (default `.enabled`) lets a host keep the close button but drop
  the prompt. Whether this session already rated is remembered in memory on the `AIChat`
  instance (cleared on reset / delete) — `/config` and history do not report it. Hosts that
  construct a new `AIChat` on every present will be asked again; keep the instance if the session
  should outlive the sheet. Sample disables interactive sheet dismiss so swipe cannot bypass Close.

### Changed

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
