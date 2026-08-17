# WCAG 2.1 AA checklist (iOS SDK-owned UI)

Target: [WCAG 2.1 Level AA](https://www.w3.org/WAI/WCAG21/quickref/?levels=aa) for UI the Diverge SDK owns
(`DivergeStatusView` / sample configure flow). Host chrome is out of scope.

Use alongside [`voiceover-checklist.md`](voiceover-checklist.md).

## Scope (v0.1)

v0.1 targets StatusView + sample only. Full AA for unfinished product UI (PDP, checkout, chat, etc.) is deferred until those surfaces ship.

## Perceivable

- [x] Text alternatives — *status UI is text-only*
- [x] Color is not the only means of conveying state — *errors use text*
- [ ] Contrast: normal text ≥ 4.5:1, large text ≥ 3:1 — ***device/visual measurement owed***
- [x] Text can resize to 200% — *sample uses `.dynamicTypeSize`*
- [x] Reflow at small widths — *vertical `ScrollView`*

## Operable

- [x] Controls reachable via VoiceOver — *labels/hints in code; device confirm on VoiceOver checklist*
- [x] Touch targets ≥ ~44×44 pt for sample button — *`minHeight: 48`*
- [x] No AT traps in SDK modals — *none in v0.1*
- [x] No flashing content

## Understandable / Robust

- [x] Labels identify inputs; blank API key error is clear
- [x] Roles/traits correct; configured state visible to AT
- [x] A11y dump contract asserted in CI

## Device sign-off

| Build / version | Tester | Date | Pass? | Notes |
|-----------------|--------|------|-------|-------|
| 0.1.0 | code baseline | 2026-08-11 | Partial | Contrast + VoiceOver device still owed |
| | | | | |
