# Changelog — Diverge SDK iOS

## [Unreleased]

### Added

- Contact, support-ticket and custom forms render in the conversation, validate locally, and
  submit through `POST /actions`. Custom-form file fields and support-ticket photos attach through
  the same photo picker as the composer. The privacy manifest now declares Name, Email address,
  Phone number and Customer support, which these forms collect; update your App Store privacy
  label.
- Livechat handover: when livechat is enabled, a header control asks for a person or ends the
  session, the composer sends to the agent while one is connected, and the agent's messages appear
  in the conversation. A reset closes an open session first.
- Livechat conversation UI: a "talk to a person" card for `request_human_agent`, centred notes when
  the visitor joins the queue, an agent joins or the session ends, system messages, agent typing,
  and tappable agent file attachments, opened through `onOpenLink` with a freshly signed link on
  each tap. While an agent is connected, the SDK tells the agent when the visitor is typing
  (`POST /livechat/typing`); it never sends the draft itself. While queued, a configured
  `livechat_waiting` form lets the visitor add details for the agent (`GET /session`,
  `PATCH /forms/{id}/values`). When a session ends while the chat is open and feedback is
  pending, the visitor is asked to rate it (`POST /livechat/feedback`).
- `AIChat.Configuration` `onLivechatSessionChange` and `AIChat.LivechatSessionInfo`: the host hears
  when the visitor is queued, talking to an agent (with the agent's name) or the session ends,
  while the chat is on screen, so it can show the agent in its own UI and offer to reopen a chat
  the visitor closed mid-session.
- Conversation rating on close: when the host sets `onClose`, a close control appears; with
  `rating: .enabled` (the default) the visitor is asked to rate the conversation (`POST /rate`)
  before the host is called. Livechat CSAT still takes precedence while a session is closed with
  pending feedback. Pass `rating: .disabled` to close without asking.
- Photo upload wire: `request_image_upload` markers and `MessageImage` parts decode from history
  and stream `done`, and visitor image/file parts travel on `POST /messages` and
  `POST /livechat/messages`.
- Photos in the conversation: image parts from the assistant, an agent or the visitor's history
  show as tiles that open full size, and an expired signed link is re-signed on tap.
- Photo attach UI: `AIChat.Attachments` and `Configuration.attachments` (default `.photoLibrary`)
  offer a PhotosPicker on the composer, on `request_image_upload` prompts, and on form/ticket
  file fields. Pass `.disabled` to hide attach and drop upload prompts.

### Fixed

- Presenting `AIChat.makeView()` from a SwiftUI sheet no longer shows a blank card: the chat keeps
  its state when the host's view re-renders. A failed first history page still shows the title and
  composer, so the visitor can type when `GET /messages` fails.

## [1.0.0] - 2026-10-01

First stable release. Upgrading from 0.1.0: see
[`Docs/integration/v1.0.0.md`](Docs/integration/v1.0.0.md).

### Added

- The conversational chat SDK: `AIChat`, `AIChat.Configuration` and `ConversationFlow` as the entire
  public surface, with `makeView()` for SwiftUI and `makeViewController()` for UIKit
- Host-owned hooks for session tokens, conversation reset and data deletion; optional per-message
  context, in-message link routing, and a choice of conversation layout
- Localization across 16 languages via a String Catalog
- Remote font loading, registered from a content-hash-keyed on-disk cache that holds one font
- `X-Diverge-SDK-Platform: ios`, `X-Diverge-SDK-Version` and `X-Diverge-Client-Profile` on
  every authenticated API call (`/config`, `/messages`). Platform and version identify the
  calling SDK release; the profile header lists every feature the build requests
  (comma-separated, `product-recommendation` today), and the backend enables the tools for the
  ones it grants, so one chat can combine features. Attachment and font downloads carry only
  the request itself. Hosts need no change
- `AIChat.Configuration(environment:)` with `DivergeAPI.Environment` (`.production` /
  `.development`), so a host can integrate against the development API. Defaults to
  `.production`, so an existing host keeps talking to the live API without changes. The iOS
  sample uses `.development` in debug builds

### Changed

- **Breaking:** the previous public API is gone — `Diverge`, `DivergeConfiguration`, `DivergeClient`,
  `DivergeError`, `Environment`, and the `DivergeSDKUI` product with `DivergeStatusView`
- Single product `AIConversation`, replacing the core/UI product split. The engine and networking
  targets are internal
- No third-party dependencies: DocC is built with `xcodebuild docbuild` instead of `swift-docc-plugin`
- Swift 6 language mode is set once at package level
- Minimum macOS raised to **15.0** (iOS floor unchanged at 18.0)

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
