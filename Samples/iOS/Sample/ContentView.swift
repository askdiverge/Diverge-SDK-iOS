import AIConversation
import SwiftUI

struct ContentView: View {
    /// Sample chrome — matches SDK AA-safe primary (~17:1 on white).
    private static let primaryText = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    /// Sample secondary — ~8.9:1 on white.
    private static let secondaryText = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)

    /// `SAMPLE_TOKEN` seeds the field so a stand-in run needs no typing.
    @State private var token = ProcessInfo.processInfo.environment["SAMPLE_TOKEN"] ?? ""
    @State private var session: ChatSession?

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

                Text("\(SampleConfig.environmentName) · \(SampleConfig.apiBaseURL.absoluteString)")
                    .font(.footnote)
                    .foregroundColor(Self.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("sample.backend")

                TextField("Session token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .frame(minHeight: 48)
                    .accessibilityLabel("Session token")
                    .accessibilityHint("Demo token only. Do not use production secrets.")

                Button("Open chat") { self.openChat() }
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
        // `SAMPLE_AUTO_OPEN` skips the tap so a stand-in run is scriptable.
        .task {
            guard
                ProcessInfo.processInfo.environment["SAMPLE_AUTO_OPEN"] != nil,
                !self.token.isEmpty
            else {
                return
            }
            self.openChat()
        }
        .sheet(item: self.$session) { session in
            session.chat.makeView()
        }
    }

    private func openChat() {
        self.session = ChatSession(chat: AIChat(Self.configuration(token: self.token)))
    }

    /// Token minting and data lifecycle stay with the host; the SDK only calls back for them.
    private static func configuration(token: String) -> AIChat.Configuration {
        .init(
            tokenProvider: { token },
            resetConversation: { token },
            deleteData: {},
            apiBaseURL: SampleConfig.apiBaseURL
        )
    }
}

/// Identity for the presented chat, so `sheet(item:)` drives presentation off the session.
private struct ChatSession: Identifiable {
    let id = UUID()
    let chat: AIChat
}
