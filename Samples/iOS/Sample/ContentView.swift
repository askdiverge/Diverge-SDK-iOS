import AIConversation
import SwiftUI

/// Holds the `AIChat` for as long as the sheet is up. `sheet(item:)` always has
/// a value, so the card cannot present empty.
private struct PresentedChat: Identifiable {
    let id = UUID()
    let chat: AIChat
}

struct ContentView: View {
    /// Sample chrome — matches SDK AA-safe primary (~17:1 on white).
    private static let primaryText = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    /// Sample secondary — ~8.9:1 on white.
    private static let secondaryText = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)

    /// Debug builds talk to the development API, release builds to production.
    #if DEBUG
    private static let environment: DivergeAPI.Environment = .development
    #else
    private static let environment: DivergeAPI.Environment = .production
    #endif

    @State private var token = ""
    @State private var presentedChat: PresentedChat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diverge Sample")
                    .font(.largeTitle)
                    .foregroundColor(Self.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h1)

                Text("Paste a session token, then open the chat.")
                    .font(.body)
                    .foregroundColor(Self.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Session token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .frame(minHeight: 48)
                    .accessibilityLabel("Session token")
                    .accessibilityHint("Demo token only. Do not use production secrets.")

                Button("Open chat") {
                    self.presentedChat = PresentedChat(chat: AIChat(Self.configuration(token: token)))
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.isEmpty)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityLabel("Open chat")
                .accessibilityHint("Presents the conversation using the token above")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .dynamicTypeSize(.small ... .accessibility3)
        // The SDK renders only the conversation; presenting and dismissing it is the host's job.
        .sheet(item: $presentedChat) { session in
            session.chat.makeView()
        }
    }

    /// Token minting and data lifecycle stay with the host; the SDK only calls back for them.
    private static func configuration(token: String) -> AIChat.Configuration {
        .init(
            tokenProvider: { token },
            resetConversation: { token },
            deleteData: {},
            environment: Self.environment
        )
    }
}
