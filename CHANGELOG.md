# Changelog — Diverge SDK iOS

## [Unreleased]

### Fixed

- While a reply streams, the conversation keeps the visitor's newest message at the top instead of
  jumping up to the previous exchange when earlier replies hold product cards.

## [1.1.0] - 2026-11-12

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
  each tap. An agent's messages show the agent's photo, or a person icon when there is none,
  instead of the assistant's avatar, and VoiceOver reads the agent's name. While an agent is
  connected, the SDK tells the agent when the visitor is typing (`POST /livechat/typing`); it never
  sends the draft itself. While queued, a configured
  `livechat_waiting` form lets the visitor add details for the agent (`GET /session`,
  `PATCH /forms/{id}/values`). When a session ends while the chat is open and feedback is
  pending, the visitor is asked to rate it (`POST /livechat/feedback`).
- `AIChat.Configuration` `onLivechatSessionChange` and `AIChat.LivechatSessionInfo`: the host hears
  when the visitor is queued, talking to an agent (with the agent's name) or the session ends,
  while the chat is on screen, so it can show the agent in its own UI and offer to reopen a chat
  the visitor closed mid-session.
- Conversation rating on close: when the host sets `onClose`, a close control appears; with
  `rating: .enabled` (the default) the visitor is asked to rate the conversation (`POST /rate`)
  before the host is called. A livechat session that closes with its own rating (CSAT) is rated
  there, so closing after it asks nothing more. Pass `rating: .disabled` to close without asking.
  Whether the visitor has rated is remembered by the `AIChat` instance, so keep it, or use
  `AIChat.configure`, to avoid asking again.
- Photo upload wire: `request_image_upload` markers and `MessageImage` parts decode from history
  and stream `done`, and visitor image/file parts travel on `POST /messages` and
  `POST /livechat/messages`.
- Photos in the conversation: image parts from the assistant, an agent or the visitor's history
  show as tiles that open full size, and an expired signed link is re-signed on tap.
- Photo attach UI: `AIChat.Attachments` and `Configuration.attachments` (default `.photoLibrary`)
  offer a PhotosPicker on the composer, on `request_image_upload` prompts, and on form/ticket
  file fields. Pass `.disabled` to hide attach and drop upload prompts. Attach is on by default, so
  upgrading starts collecting photos: the privacy manifest now declares Photos or videos; update
  your App Store privacy label, or pass `.disabled`.

- A "Show earlier messages" control above the conversation loads older history, and retries a
  first page that failed. Visitors previously saw only the newest page.

- The "talk to a person" card offers "No thanks", which removes the card and keeps the chat with
  the assistant, as the web widget does.
- A livechat session the backend closes for inactivity ends with its own note, telling the visitor
  they can continue with the assistant or contact customer service again.

### Changed

- Forms and "talk to a person" cards restored from history are read-only, as on the web widget;
  only those in a reply received while the chat is open can be filled or accepted, including
  after the visitor closes and reopens the chat from the same `AIChat`.

### Fixed

- Presenting `AIChat.makeView()` from a SwiftUI sheet no longer shows a blank card: the chat keeps
  its state when the host's view re-renders. A failed first history page still shows the title and
  composer, so the visitor can type when `GET /messages` fails.
- The chat no longer goes blank after a data deletion, an expired session or a failed history
  load: the welcome message stays on screen and the visitor can keep writing.
- A message refused because the session expired goes back in the composer, with its photos, so the
  visitor can send it again.
- Leaving the livechat queue or ending a chat with an agent now asks the visitor to confirm, as the
  web chat does, so a stray tap doesn't lose their place.
- Reopening the chat during a livechat session shows the queue or agent note again, and the
  waiting form fades along its bottom edge when there is more to scroll to.
- The jump-to-newest button sits in the trailing corner, clear of a form's Submit label, and no
  longer lingers on a conversation with nothing to scroll to. Wrapped bullet lines align under
  their text.
- Text scales with Dynamic Type on chatbots with no custom font.
- A heading in an assistant reply (`### Delivery`) shows as a bold line, as on the web widget,
  instead of with its `#` marks.
- A product or table image that fails to load shows a placeholder instead of an empty slot.
- A sent message always lifts to the top of the conversation: an answer that arrived in quick
  parts could leave it short, with the reply below the fold.
- A notice shown again soon after it went away, such as "Couldn't load older messages", stays up for
  its full time instead of disappearing early.
- A failed save of the waiting form says so beside Save, and a field with an error scrolls into
  view, instead of both staying out of sight inside the card.
- A form no longer repeats "Fill in at least 1 field" when its required fields already say what is
  missing, and the message clears as soon as the visitor edits the form.
- The jump-to-newest button stays off a form field while it has the keyboard.
- A form field near the end of the newest reply scrolls clear of the composer while the visitor
  types in it, and the form's Submit button can be scrolled into view without closing the keyboard.
- Long form field labels wrap instead of being cut off, a dropdown shows the same red outline as a
  text field when it has an error, and a picked form photo no longer shows the field's raw key.
- A rich text, table or products part the SDK can't read is left out, and the rest of the reply
  still shows: it used to end the reply mid-stream, or stop a page of older messages or a live
  chat update from loading.
- Links and bold text written in Markdown in the configured subtitle, such as a link to the
  privacy policy, render as links and bold, as on the web widget, instead of showing their
  brackets and asterisks. The links open through `onOpenLink`, or the browser when it isn't set.
- A message the visitor sends before their previous one has a reply, such as a second message to
  a livechat agent, scrolls into view instead of staying hidden below the composer.

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
