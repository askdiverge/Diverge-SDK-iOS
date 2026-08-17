# Privacy (iOS) — v0.1 contract

## Current SDK surface

v0.1.0 does **not** access camera, photos, location, microphone, contacts, or advertising identifiers.

The shipped Privacy Manifest [`Sources/DivergeSDK/PrivacyInfo.xcprivacy`](../../Sources/DivergeSDK/PrivacyInfo.xcprivacy) declares:

- `NSPrivacyTracking` = `false`
- Empty tracking domains, collected data types, and accessed API types

**No required-reason API declarations** are needed until the SDK actually calls those APIs (file timestamps, UserDefaults, disk space, boot time, etc.). Do not declare APIs “just in case.”

**No Info.plist usage-description keys** are required for host apps solely because they embed this SDK at v0.1. Keep the template below for future features.

## When adding permissions later

1. Audit source for required-reason APIs and update `PrivacyInfo.xcprivacy` with correct reason codes only.
2. Fill real copy in [`Info.plist.usage-descriptions.template.md`](Info.plist.usage-descriptions.template.md) and document in the per-release integration guide.
3. Update [`Docs/site/att.html`](../site/att.html) if tracking behavior changes.

Host apps always own ATT prompts. See ATT docs on the public site.
