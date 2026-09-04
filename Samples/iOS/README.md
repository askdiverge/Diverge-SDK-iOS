# Diverge iOS sample

SwiftUI app that configures `AIConversation` with a session token and presents the chat in a sheet.

## Open and run

1. Open `Sample.xcodeproj` in a Swift 6–capable Xcode (CI uses newest stable / Xcode 26+).
2. Select an iOS 18+ simulator.
3. Run **Sample**.
4. Paste a session token and tap **Open chat**.

The token, conversation reset, and data deletion are supplied by the host through
`AIChat.Configuration`; the SDK renders the conversation and nothing else, so presenting and
dismissing it is the host's responsibility.

## Regenerating the Xcode project (optional)

```bash
brew install xcodegen
cd Samples/iOS
xcodegen generate
./../../scripts/sync-version.sh
```
