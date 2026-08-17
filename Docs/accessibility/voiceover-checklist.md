# VoiceOver test checklist (iOS)

Use this process before each release that changes UI surfaced by the SDK.
Also complete [`wcag-2.1-aa-checklist.md`](wcag-2.1-aa-checklist.md).
Reference: https://developer.apple.com/documentation/accessibility/supporting-voiceover-in-your-app

## Scope (v0.1)

Applies to `DivergeStatusView` and the iOS sample configure flow only. Full product UI AA is deferred until those surfaces ship.

## Implementation status (engineering)

| Area | Status |
|------|--------|
| Process + this checklist | Done |
| Labels / headers / hints in StatusView + sample | Done |
| AA-safe text colors (primary `#1A1A1A`, secondary `#4A4A4A`) | Done |
| Touch targets ≥ 48 pt (sample field + button) | Done |
| CI a11y string-dump contract (`DivergeStatusViewA11yTests`) | Done |
| Physical-device VoiceOver gesture sign-off | Operator — fill table below |

## Legend

| Mark | Meaning |
|------|---------|
| Code baseline | Covered by labels in source and/or a11y contract unit tests |
| Device owed | Requires physical-device (or Simulator VoiceOver) sign-off below |

## Setup (device owed)

1. Open `Samples/iOS/DivergeSample` on a device or Simulator (iOS 18+).
2. Settings → Accessibility → VoiceOver → On (or triple-click Side Button if configured).
3. Confirm rotor includes Headings, Form Controls.
4. Return to the sample app.

## Smoke checks

- [x] All interactive controls are focusable and have spoken labels — *code baseline: sample TextField/Button labels + hints*
- [x] Images that convey meaning have accessibility labels; decorative images are hidden — *no images in v0.1.0 SDK UI*
- [x] Dynamic type / large content sizes do not clip critical text — *sample `.dynamicTypeSize(.small ... .accessibility3)`*
- [x] Focus order follows visual reading order — *code baseline: single vertical stack; confirm on device*
- [x] Modals/sheets move VoiceOver focus into the dialog and restore on dismiss — *N/A for v0.1.0 (no SDK sheets)*
- [x] Loading and error states are announced — *configure errors shown as labeled text*
- [x] Custom controls expose traits (button, selected, etc.) correctly — *SwiftUI Button + header traits / headings*

## Gestures to exercise (device owed)

Run once per release that touches SDK UI; then update the sign-off table.

- [ ] Swipe right/left through: title → instructions → API key → Configure → (error if any) → StatusView children
- [ ] Double-tap **Configure sandbox** with a blank key; confirm error is spoken
- [ ] Double-tap **Configure sandbox** with `sk_sandbox_demo`; confirm StatusView speaks version + environment + URL
- [ ] Escape / two-finger Z — *N/A (no sheets in v0.1)*

## Automated coverage (CI)

`DivergeStatusViewA11yTests` asserts the accessibility string-dump contract (`swift test` / GitHub Actions `iOS` workflow).

## Device sign-off

| Build / version | Tester | Date | Device | Pass? | Notes |
|-----------------|--------|------|--------|-------|-------|
| 0.1.0 | code baseline (static + automated) | 2026-08-17 | — | Partial | Gestures still need a human AT pass |
| | | | | | |
