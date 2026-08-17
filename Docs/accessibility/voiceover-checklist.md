# VoiceOver test checklist (iOS)

Use this process before each release that changes UI surfaced by the SDK.
Also complete [`wcag-2.1-aa-checklist.md`](wcag-2.1-aa-checklist.md).
Reference: https://developer.apple.com/documentation/accessibility/supporting-voiceover-in-your-app

## Scope (v0.1)

Applies to `DivergeStatusView` and the iOS sample configure flow only. Full product UI AA is deferred until those surfaces ship.

## Legend

| Mark | Meaning |
|------|---------|
| Code baseline | Covered by labels in source and/or a11y contract unit tests |
| Device owed | Requires physical-device (or Simulator VoiceOver) sign-off below |

## Setup (device owed)

- [ ] Enable VoiceOver on a physical device (Settings → Accessibility → VoiceOver)
- [ ] Confirm rotor includes Headings, Links, Form Controls, Containers
- [ ] Use the sample app or host integration that embeds SDK UI

## Smoke checks

- [x] All interactive controls are focusable and have spoken labels — *code baseline: sample TextField/Button labels + hints*
- [x] Images that convey meaning have accessibility labels; decorative images are hidden — *no images in v0.1.0 SDK UI*
- [x] Dynamic type / large content sizes do not clip critical text — *sample `.dynamicTypeSize(.small ... .accessibility3)`*
- [x] Focus order follows visual reading order — *code baseline: single vertical stack; **device owed** to confirm*
- [x] Modals/sheets move VoiceOver focus into the dialog and restore on dismiss — *N/A for v0.1.0 (no SDK sheets)*
- [x] Loading and error states are announced — *configure errors shown as labeled text*
- [x] Custom controls expose traits (button, selected, etc.) correctly — *SwiftUI Button + header traits on status title*

## Gestures to exercise (device owed)

- [ ] Swipe right/left through the full screen hierarchy
- [ ] Double-tap to activate primary actions
- [ ] Escape / two-finger Z to dismiss sheets where applicable

## Automated coverage (CI)

`DivergeStatusViewA11yTests` asserts the accessibility string-dump contract (`swift test` / GitHub Actions `iOS` workflow).

## Device sign-off

| Build / version | Tester | Date | Device | Pass? | Notes |
|-----------------|--------|------|--------|-------|-------|
| 0.1.0 | code baseline (static + automated) | 2026-08-11 | — | Partial | Gesture rows still blank |
| | | | | | |
