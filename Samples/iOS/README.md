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

Debug builds talk to the development API and release builds to production, via
`AIChat.Configuration(environment:)` in `ContentView.swift`. The SDK itself defaults to
`.production`, so a host that says nothing keeps talking to the live API.

Never put a chatbot API key in the sample — it would ship in the app. Paste a visitor JWT into
the token field instead.

## Regenerating the Xcode project (optional)

```bash
brew install xcodegen
cd Samples/iOS
xcodegen generate
./../../scripts/sync-version.sh
```
