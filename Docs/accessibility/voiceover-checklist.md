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
- Product open CTA (label from `/config` or localised "View product"; hint "Opens the product page") and optional add-to-cart sibling button (label "Add to cart"; hint "Adds this product to your cart") on cards that carry a sku; splash badge on the image is decorative; product cards stay interactive while a reply streams
- Start-prompt chips (`start_prompts` on `/config`): each chip's label is its `prompt_text` and its hint is "Sends this starter as your next message"; chips sit below the welcome turn, wrap when a label is wider than the list, disappear after the first user turn (the footer row is omitted, not left empty), and are hidden while a reply streams
- Assistant image and file attachments (label = caption / filename + size; hint only while openable; unavailable state spoken when the signed URL failed or expired)
- Guided upload-photo prompt (`request_image_upload`): one button whose label is the prompt line and whose hint is "Opens the photo picker"; disabled while a photo encodes or a reply streams; absent when the host set attachments to `.disabled`
- Livechat: toolbar person control (request / leave; offline presents a top notice; value speaks localised available/offline); `request_human_agent` marker card (prompt body, CTA, distinct hint); agent turns speak the agent display name (localised “Agent” fallback); centred session notes (queued / joined / ended); agent typing indicator (format “{name} is typing…”); composer placeholder switches while waiting / active; session-ended alert when the poller sees a 401
- In-conversation forms (`show_contact_form` / `show_support_ticket` / `show_form`): card labelled with the form title (contact / ticket / custom `name`); hint "Fill in the fields and submit" while editable, "This form can no longer be edited" when it sits above a newer bot turn (also shown as a visible caption in place of Submit); each text input and dropdown is labelled with its field label (required fields carry the "Required" hint; dropdowns speak the current selection or "Select an option"); required fields announce their validation errors; submit button disabled while submitting / encoding / streaming; a "Done" button sits above the keyboard while a form field is focused; submitted state collapses to a checkmark + confirmation
- Conversation rating on close: close control labelled "Close"; overlay titled "How good was the chatbot?"; conversation, composer and Close are hidden from VoiceOver while the overlay is up; each of the five numbered buttons speaks its satisfaction label ("Very unsatisfied" … "Very satisfied"); Skip on the scale dismisses without submitting; Skip on the feedback step sends the score without written feedback (hint distinguishes the two); scores 1–3 open a feedback field (placeholder spoken) with "Submit feedback" and a keyboard "Done" bar (`form.done`); a failed 4–5 submit stays on the overlay — retry is re-tapping the same score (no dedicated Retry button); a second Close after a successful rating dismisses without re-asking when the host keeps the `AIChat` instance
- Composer photo attachments: attach control (label "Attach photo"; disabled while a photo encodes or a reply streams, with the encoding spinner in place of the glyph), the pending chip strip (each chip is one combined element — generic image label, then "Remove photo" as the action), and the user-pane echo tile (a plain image element with the generic image label — inline `data:` uploads have nowhere to open to, so they are not buttons and do not dim)
- Older-history loading: the top-edge spinner ("Loading earlier messages") and the load-failed bar (message + "Retry" button)
- Chat input, send control, jump-to-bottom control
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
- [ ] Product cards: each card speaks title (+ description / splash); activating opens the product page with the open hint; when add-to-cart is offered (config + host hook + sku), a sibling button speaks "Add to cart" with its hint; cards stay interactive while a reply streams
- [ ] Send a message and confirm the arriving reply is announced
- [ ] Attach a photo: the attach control announces its disabled state while encoding, the chip appears as one element reading the image label and "Remove photo", removing it returns focus to the composer, and the sent echo reads as an image (not a button) with the image label and no open hint
- [ ] Guided upload prompt: the card reads the prompt line with hint "Opens the photo picker"; activating it presents the picker; while encoding or streaming the card is disabled; with `attachments: .disabled` the card is absent from the tree (the disabled-while-streaming and absent-when-disabled states are also pinned by the stand-in XCUITest — `isEnabled == false` during a held stream, no matching button with attachments disabled; the spoken pass is still to do)
- [ ] In-conversation form: swipe onto the card (title spoken), fill a required field via the Form Controls rotor (each input reads its field label, required ones the "Required" hint; the dropdown reads its label and selection), activate "Done" above the keyboard, activate Submit; after success the card collapses to the confirmation; an older form after a newer bot reply reads as read-only and shows the caption in place of Submit (the visible states are pinned by the stand-in XCUITest `FormsTests` in both flows; the spoken pass is still to do)
- [ ] Conversation rating: activate Close; the overlay reads the title and five score buttons by satisfaction label and the conversation under it is not in the rotor; activate 5 to submit and dismiss, or 2 then type feedback and Submit / Skip (Skip still records the score); a failed 4–5 submit keeps focus on the overlay with the error announced — retry by activating the same score again; a second Close after a successful rating dismisses without re-asking (Sample reuses `AIChat`; spoken pass still to do)
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
