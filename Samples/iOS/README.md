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

## Choosing a backend

The build configuration picks the Chatbot API host, via `Config/*.xcconfig` → `Info.plist` →
`SampleConfig`. The running app shows the active environment and URL under the title.

| Configuration | Host |
| ------------- | ---- |
| `Development` (default) | `https://dev.api.dialogintelligens.dk` |
| `Production` | `https://api.dialogintelligens.dk` |
| `Local` | `http://127.0.0.1:3000` |
| `Release` | `https://api.dialogintelligens.dk` |

`Local` exists so the SDK can be driven against a stand-in backend on the Mac — simulator
loopback is the host machine, and the sample carries `NSAllowsLocalNetworking` for it. To
override a host without editing tracked files, copy `Config/Secrets.xcconfig.example` to
`Config/Secrets.xcconfig` (gitignored); it is included last, so it wins.

Never put a chatbot API key in an xcconfig — it would ship in the app. Only visitor JWTs, pasted
into the token field, belong in the sample.

The SDK itself defaults to production: `AIChat.Configuration(apiBaseURL:)` defaults to
`DivergeAPI.productionBaseURL`, so a host that says nothing keeps talking to the live API.

## Scripting a run

Two launch-environment affordances keep a stand-in run typing-free:

```bash
xcrun simctl launch \
  --terminate-running-process <device> ai.askdiverge.sample
# with:
#   SIMCTL_CHILD_SAMPLE_TOKEN=<visitor-jwt>   seeds the token field
#   SIMCTL_CHILD_SAMPLE_AUTO_OPEN=1           presents the chat without a tap
```

## Regenerating the Xcode project (optional)

```bash
brew install xcodegen
cd Samples/iOS
xcodegen generate
./../../scripts/sync-version.sh
```
