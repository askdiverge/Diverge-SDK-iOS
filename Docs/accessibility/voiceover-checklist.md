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
- Product cards and grids, tables
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

- [ ] Swipe through a full exchange: input → sent turn → streaming reply → product card / table children
- [ ] Send a message and confirm the arriving reply is announced
- [ ] Open and dismiss the privacy and delete-data sheets; confirm focus moves and returns
- [ ] Escape / two-finger Z from each sheet

## Automated coverage (CI)

None. There are no accessibility tests in the suite.

## Device sign-off

| Build / version | Tester | Date | Device | Pass? | Notes |
|-----------------|--------|------|--------|-------|-------|
| | | | | | |
