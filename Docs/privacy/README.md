# Privacy (iOS) — v0.1 contract

## Current SDK surface

The SDK does **not** access the camera, location, microphone, contacts, or advertising identifiers.
Photos reach it only when the user picks one in SwiftUI's `PhotosPicker`, which runs out of process
and hands over just the chosen image; the SDK never reads the photo library itself. Hosts turn this
off with `attachments: .disabled`.

The shipped Privacy Manifest [`Sources/AIConversation/PrivacyInfo.xcprivacy`](../../Sources/AIConversation/PrivacyInfo.xcprivacy) declares:

- `NSPrivacyTracking` = `false`
- Empty tracking domains and accessed API types
- Collected data types, each linked to the user, not used for tracking, for app functionality:
  - `OtherUserContent` — typed messages and the optional context string are sent to the assistant
    backend to generate replies
  - `Name`, `EmailAddress`, `PhoneNumber` — what the user enters in contact, support-ticket and
    custom forms
  - `CustomerSupport` — the support request a support ticket carries
  - `PhotosorVideos` — photos the user attaches are sent with the message or form they belong to

**No required-reason API declarations** are needed until the SDK actually calls those APIs (file timestamps, UserDefaults, disk space, boot time, etc.). Do not declare APIs “just in case.”

**No Info.plist usage-description keys** are required for host apps solely because they embed this SDK: `PhotosPicker` needs no `NSPhotoLibraryUsageDescription`. Keep the template below for future features.

## When adding permissions later

1. Audit source for required-reason APIs and update `PrivacyInfo.xcprivacy` with correct reason codes only.
2. Fill real copy in [`Info.plist.usage-descriptions.template.md`](Info.plist.usage-descriptions.template.md) and document in the per-release integration guide.
3. Update [`Docs/site/att.html`](../site/att.html) if tracking behavior changes.

Host apps always own ATT prompts. See ATT docs on the public site.
