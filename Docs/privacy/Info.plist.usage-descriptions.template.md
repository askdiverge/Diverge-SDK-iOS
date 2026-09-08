# Info.plist usage-description template (host app)

Copy the keys the SDK actually needs into the **host app** Info.plist.
Missing usage strings crash the host app on first access of the related API.

## v0.1.0 — send photos

**None required for the photo-library attach path.** The composer uses SwiftUI
`PhotosPicker` (`PHPickerViewController`), which runs out-of-process and does
**not** need `NSPhotoLibraryUsageDescription`. Do not add that key solely for
SDK photo attach — it would trigger an unnecessary permission prompt.

Camera capture, saving to the library, and documents (`fileImporter`) are
**not** in this release; add the matching keys below only when those land.

## Future features (fill copy when confirmed)

| Key | When needed | Example purpose string |
|-----|-------------|------------------------|
| `NSCameraUsageDescription` | Camera capture | "Diverge uses the camera to scan products." |
| `NSPhotoLibraryUsageDescription` | Direct Photos framework access (not PhotosPicker) | "Diverge accesses your photos to upload product images." |
| `NSPhotoLibraryAddUsageDescription` | Save photos | "Diverge saves images to your photo library." |
| `NSLocationWhenInUseUsageDescription` | Location while in use | "Diverge uses your location to show nearby availability." |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Background location | Only if required; prefer When In Use. |
| `NSUserTrackingUsageDescription` | ATT / tracking | "This identifier helps measure campaign effectiveness." |
| `NSContactsUsageDescription` | Contacts | Only if the SDK reads contacts. |
| `NSMicrophoneUsageDescription` | Microphone | Only if audio capture is used. |

## XML snippet (placeholders only)

```xml
<!-- Add only the keys the integrated SDK features require -->
<key>NSCameraUsageDescription</key>
<string>TODO: Replace with approved camera usage copy.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>TODO: Replace with approved photo library usage copy.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>TODO: Replace with approved location usage copy.</string>
<key>NSUserTrackingUsageDescription</key>
<string>TODO: Replace with approved tracking usage copy.</string>
```

Reference: https://developer.apple.com/documentation/bundleresources/information-property-list
