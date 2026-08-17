# WCAG 2.1 AA checklist (iOS SDK-owned UI)

Target: [WCAG 2.1 Level AA](https://www.w3.org/WAI/WCAG21/quickref/?levels=aa) for UI the Diverge SDK owns
(`DivergeStatusView` / sample configure flow). Host chrome is out of scope.

Use alongside [`voiceover-checklist.md`](voiceover-checklist.md).

## Scope (v0.1)

v0.1 targets StatusView + sample only. Full AA for unfinished product UI (PDP, checkout, chat, etc.) is deferred until those surfaces ship.

## Contrast (calculated)

Fixed colors used by StatusView / sample (sRGB relative luminance, WCAG formula):

| Pair | Ratio | AA normal text (≥ 4.5:1) |
|------|-------|---------------------------|
| `#1A1A1A` on `#FFFFFF` | ≈ 17.4:1 | Pass |
| `#4A4A4A` on `#FFFFFF` | ≈ 8.9:1 | Pass |
| `#1A1A1A` on `#F7F5F2` | ≈ 16.0:1 | Pass |
| `#4A4A4A` on `#F7F5F2` | ≈ 8.1:1 | Pass |
| `#8B0000` on light-red wash (`#FFE0E0`) | ≈ 5.9+:1 | Pass |

Re-run the table if colors change. Spot-check on device for Dynamic Type / Dark Mode host overrides.

## Perceivable

- [x] Text alternatives — *status UI is text-only*
- [x] Color is not the only means of conveying state — *errors use text*
- [x] Contrast: normal text ≥ 4.5:1, large text ≥ 3:1 — *fixed AA-safe palette above*
- [x] Text can resize to 200% — *sample uses `.dynamicTypeSize`*
- [x] Reflow at small widths — *vertical `ScrollView`*

## Operable

- [x] Controls reachable via VoiceOver — *labels/hints/headings in code; device confirm on VoiceOver checklist*
- [x] Touch targets ≥ ~44×44 pt for sample button / field — *`minHeight: 48`*
- [x] No AT traps in SDK modals — *none in v0.1*
- [x] No flashing content

## Understandable / Robust

- [x] Labels identify inputs; blank API key error is clear
- [x] Roles/traits correct; configured state visible to AT
- [x] A11y dump contract asserted in CI

## Device sign-off

| Build / version | Tester | Date | Pass? | Notes |
|-----------------|--------|------|-------|-------|
| 0.1.0 | code baseline + calculated contrast | 2026-08-17 | Partial | VoiceOver gestures still owed on device |
| | | | | |
