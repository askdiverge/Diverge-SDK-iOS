import AIConversation
import SwiftUI

struct ContentView: View {
    /// Sample chrome — matches SDK AA-safe primary (~17:1 on white).
    private static let primaryText = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    /// Sample secondary — ~8.9:1 on white.
    private static let secondaryText = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)

    @State private var token = ""
    @State private var chat: AIChat?
    @State private var isChatPresented = false

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
                    chat = AIChat(Self.configuration(token: token))
                    isChatPresented = true
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
        .sheet(isPresented: $isChatPresented) {
            if let chat {
                chat.makeView()
            }
        }
    }

    /// Token minting and data lifecycle stay with the host; the SDK only calls back for them.
    private static func configuration(token: String) -> AIChat.Configuration {
        .init(
            tokenProvider: { token },
            resetConversation: { token },
            deleteData: {}
        )
    }
}
