# Diverge iOS sample

SwiftUI app that configures sandbox via `DivergeSDK` and shows status with `DivergeSDKUI`.

## Open and run

1. Open `DivergeSample.xcodeproj` in a Swift 6–capable Xcode (CI uses newest stable / Xcode 26+).
2. Select an iOS 18+ simulator.
3. Run **DivergeSample**.
4. Tap **Configure sandbox** (default key `sk_sandbox_demo`).

## Regenerating the Xcode project (optional)

```bash
brew install xcodegen
cd Samples/iOS
xcodegen generate
./../../scripts/sync-version.sh
```
