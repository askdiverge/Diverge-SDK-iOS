# VoiceOver test checklist (iOS)

Use this process before each release that changes UI surfaced by the SDK.
Also complete [`wcag-2.1-aa-checklist.md`](wcag-2.1-aa-checklist.md).
Reference: https://developer.apple.com/documentation/accessibility/supporting-voiceover-in-your-app

## Status: not yet audited

The SDK's conversation UI has had no accessibility audit. Nothing below is signed off, and the
absence of ticks is accurate rather than pending paperwork.

Surfaces that need covering:

- Conversation list: user turns, assistant turns, streaming updates
- Text bubbles, including inline emphasis and links
- Product cards and grids, suggestion cards and grids, tables
- Product open CTA (label from `/config` or localised "View product"; hint "Opens the product page") and optional add-to-cart sibling button (label "Add to cart"; hint "Adds this product to your cart") on cards that carry a sku when `/config` enables cart (host hook or link-mode URL); splash badge on the image is decorative; product cards stay interactive while a reply streams
- Start-prompt chips (`start_prompts` on `/config`): each chip's label is its `prompt_text` and its hint is "Sends this starter as your next message"; chips sit below the welcome turn, wrap when a label is wider than the list, disappear after the first user turn (the footer row is omitted, not left empty), and are hidden while a reply streams
- Assistant image and file attachments (label = caption / filename + size; hint only while openable; unavailable state spoken when the signed URL failed or expired)
- Guided upload-photo prompt (`request_image_upload`): one button whose label is the prompt line and whose hint is "Opens the photo picker"; disabled while a photo encodes or a reply streams; absent when the host set attachments to `.disabled`
- Quick-reply chips (`quick_replies` parts): same chip contract as start prompts; only the newest bot turn's chips are in the tree (older turns drop them), and the row dims and disables while a reply streams
- In-chat banners (`GET /banners`): each card is a container (`banner.<id>`) holding the message text, an optional CTA button (label = CTA text; hint "Opens the link") and a "Dismiss" button (≥ 44 pt)
- Toolbar: close control labelled "Close" (present only when the host passes `onClose`), reset control labelled "Reset conversation"
- Composer photo attachments: attach control (label "Attach photo"; disabled while a photo encodes or a reply streams, with the encoding spinner in place of the glyph), the pending chip strip (each chip is one combined element — generic image label, then "Remove photo" as the action), and the user-pane echo tile (a plain image element with the generic image label — inline `data:` uploads have nowhere to open to, so they are not buttons and do not dim)
- Older-history loading: the top-edge spinner ("Loading earlier messages") and the load-failed bar (message + "Retry" button)
- Chat input, send control (label "Send message"), jump-to-bottom control
- Header logo and subtitle
- Privacy and delete-data sheets
- Loading, error and notice states

## Legend

| Mark | Meaning |
|------|---------|
| Code baseline | Covered by labels in source and/or a11y contract unit tests |
| Device owed | Requires physical-device (or Simulator VoiceOver) sign-off below |

## Setup

1. Open `Samples/iOS/Sample` on a device or Simulator (iOS 18+).
2. Settings → Accessibility → VoiceOver → On (or triple-click Side Button if configured).
3. Confirm rotor includes Headings, Form Controls.
4. Return to the sample app and open the chat.

## Smoke checks

- [ ] All interactive controls are focusable and have spoken labels
- [ ] Images that convey meaning have accessibility labels; decorative images are hidden
- [ ] Dynamic type / large content sizes do not clip critical text
- [ ] Focus order follows visual reading order
- [ ] Sheets move VoiceOver focus into the dialog and restore it on dismiss
- [ ] Loading, streaming and error states are announced
- [ ] Custom controls expose traits (button, selected, etc.) correctly

## Gestures to exercise

Run once per release that touches SDK UI; then update the sign-off table.

- [ ] Swipe through a full exchange: input → sent turn → streaming reply → product / suggestion card / table / image / file children
- [ ] Start-prompt chips: on a welcome-only conversation the chips sit after the welcome bubble; each speaks its prompt text with the send hint; activating one sends the text and the chips leave the tree; after a reset they return
- [ ] Product cards: each card speaks title (+ description / splash); activating opens the product page with the open hint; when add-to-cart is offered (config + sku + host hook or link URL), a sibling button speaks "Add to cart" with its hint; cards stay interactive while a reply streams
- [ ] Send a message and confirm the arriving reply is announced
- [ ] Attach a photo: the attach control announces its disabled state while encoding, the chip appears as one element reading the image label and "Remove photo", removing it returns focus to the composer, and the sent echo reads as an image (not a button) with the image label and no open hint
- [ ] Guided upload prompt: the card reads the prompt line with hint "Opens the photo picker"; activating it presents the picker; while encoding or streaming the card is disabled; with `attachments: .disabled` the card is absent from the tree (the disabled-while-streaming and absent-when-disabled states are also pinned by the stand-in XCUITest — `isEnabled == false` during a held stream, no matching button with attachments disabled; the spoken pass is still to do)
- [ ] Scroll up in a conversation with more than one history page: the top-edge spinner is announced as "Loading earlier messages" while the page loads and is gone (no lingering element) once it lands; the turn VoiceOver was on before the load stays focused and is not re-read; after a failed load the top-edge bar reads "Couldn't load older messages" followed by a "Retry" button (≥ 44 pt) that starts the load again, and the bar is gone once the retry starts
- [ ] Open and dismiss the privacy and delete-data sheets; confirm focus moves and returns
- [ ] Escape / two-finger Z from each sheet

## Automated coverage (CI)

Contract-level only — `MessageMediaAccessibilityTests` pins the label / hint / unavailable copy
of image and file tiles and which URL schemes are tappable. Nothing exercises VoiceOver itself.

## Device sign-off

| Build / version | Tester | Date | Device | Pass? | Notes |
|-----------------|--------|------|--------|-------|-------|
| | | | | | |
