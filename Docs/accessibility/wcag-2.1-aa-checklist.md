# WCAG 2.1 AA checklist (iOS SDK-owned UI)

Target: [WCAG 2.1 Level AA](https://www.w3.org/WAI/WCAG21/quickref/?levels=aa) for UI the Diverge SDK
owns — the conversation view, its bubbles, product cards, tables, input and sheets. Host chrome
(navigation bar, presentation) is out of scope.

Use alongside [`voiceover-checklist.md`](voiceover-checklist.md).

## Status: not yet audited

The SDK's conversation UI has had no accessibility audit. Nothing below is signed off.

## Contrast is deployment-dependent

The SDK's palette is supplied by the remote theme configuration, so contrast **cannot be guaranteed
by the SDK**. Whatever a customer configures is what renders. Two consequences:

- Contrast has to be validated per deployment, against that customer's theme, not once here.
- The SDK's own fallback palette (used until the remote theme resolves, and when a colour fails to
  parse) is fixed and should be measured once. That measurement is outstanding.

Whoever runs the audit should decide whether the SDK ought to reject or correct a configured palette
that fails AA, or whether that stays the customer's responsibility. That is a product decision, not
an implementation detail.

## Perceivable

- [ ] Text alternatives for images that convey meaning (product imagery, avatar, header logo)
- [ ] Colour is not the only means of conveying state
- [ ] Contrast: normal text ≥ 4.5:1, large text ≥ 3:1 — see the note above
- [ ] Text resizes to 200% without loss of content or function
- [ ] Reflow at small widths and large text sizes

## Operable

- [ ] All controls reachable and operable via VoiceOver
- [ ] Touch targets ≥ ~44×44 pt
- [ ] No AT traps in the SDK's sheets
- [ ] No flashing content; streaming and thinking animations respect Reduce Motion

## Understandable / Robust

- [ ] Labels identify inputs; error and notice states are clear
- [ ] Roles and traits are correct, including for custom controls
- [ ] Streaming replies announce without flooding the AT queue

## Device sign-off

| Build / version | Tester | Date | Pass? | Notes |
|-----------------|--------|------|-------|-------|
| | | | | |
