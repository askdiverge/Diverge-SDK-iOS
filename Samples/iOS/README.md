# Diverge iOS sample

SwiftUI app that configures `AIConversation` with a session token and presents the chat in a sheet.

End-to-end local vs production setup: [`docs/analysis/ios-sdk-local-dev.md`](../../../docs/analysis/ios-sdk-local-dev.md) (workspace) or the steps below.

## Open and run

1. Open `Sample.xcodeproj` in a Swift 6–capable Xcode (CI uses newest stable / Xcode 26+).
2. Select an iOS 18+ simulator.
3. In the scheme, pick **Development**, **Production**, or **Local** (toolbar, next to Run).
4. Run **Sample**. The screen shows the URL from `Config/*.xcconfig`.
5. Paste a visitor JWT minted against that same host and tap **Open chat**. You can still switch backends in the picker without rebuilding.
6. Optional **Page / URL** field is `AIChat.Configuration.contextProvider`. Dashboard start-prompt
   `url_pattern`s and in-chat banner patterns are a literal substring of this string, evaluated when
   the chat view bootstraps (banners via `GET /api/v1/chat/banners?url=`). Use a path or full URL
   (`/products`, `https://shop.example.com/products/123`), not only a SKU label, if per-page chips
   or banners should appear. UITests can seed it with `SAMPLE_PAGE`.

## xcconfig

| Configuration | File | API |
|---------------|------|-----|
| Development (default) | `Config/Development.xcconfig` | `https://dev.api.dialogintelligens.dk` |
| Production | `Config/Production.xcconfig` | `https://api.dialogintelligens.dk` |
| Local | `Config/Local.xcconfig` | `http://127.0.0.1:3000` |
| Release | `Config/Release.xcconfig` | production |

Optional overrides: copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` (gitignored). Do not put API keys in xcconfig — they would ship in the app.

Mint a token (API key stays on your machine, not in the app):

```bash
# production (default)
CHATBOT_API_KEY='…' CHATBOT_ID='your-bot-id' ./scripts/mint-visitor-token.sh

# shared development API
ENV=development CHATBOT_API_KEY='…' CHATBOT_ID='your-bot-id' ./scripts/mint-visitor-token.sh

# local compose
ENV=local CHATBOT_API_KEY='…' CHATBOT_ID='your-bot-id' ./scripts/mint-visitor-token.sh
```

The token, conversation reset, data deletion, and optional `apiBaseURL` are supplied by the host through
`AIChat.Configuration`; the SDK renders the conversation and nothing else, so presenting and
dismissing it is the host's responsibility. The sample wires `onOpenLink` (records the URL, then
opens it unless `SAMPLE_STANDIN=1`) and `onAddToCart` (shows last-added product in the sheet inset).

## Stand-in UITests

End-to-end suites live in [`Tests/Standin/`](../../Tests/Standin/README.md). They launch this Sample
(Local, `http://127.0.0.1:3000`) against Python stand-in servers:

```bash
make uitest
# or one class: ./Tests/Standin/run-uitests.sh HistoryTests
```

## Regenerating the Xcode project (optional)

```bash
brew install xcodegen
cd Samples/iOS
xcodegen generate
./../../scripts/sync-version.sh
```
