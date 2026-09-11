import AIConversation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    /// Sample chrome — matches SDK AA-safe primary (~17:1 on white).
    private static let primaryText = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
    /// Sample secondary — ~8.9:1 on white.
    private static let secondaryText = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)

    /// Stable sheet identity — `sheet(isPresented:)` + `if let chat` can present an empty
    /// sheet on iOS; `sheet(item:)` keeps the chat view tied to the presented item.
    private struct ChatSession: Identifiable {
        let id = UUID()
        let chat: AIChat
    }

    @State private var token = ""
    @State private var backend: Backend = .fromBuildSettings
    @State private var session: ChatSession?
    @State private var conversationFlow: AIChat.ConversationFlow = .topDown
    @State private var appearance: AIChat.Appearance = .system
    @State private var attachments: AIChat.Attachments = .photoLibrary
    /// Page / URL string forwarded as `contextProvider` so start-prompt `url_pattern`s can match.
    @State private var page = ""
    /// Recreated when token, backend, conversation flow, appearance, attachments, or page change.
    @State private var chat: AIChat?
    @State private var chatBoundTo: String?
    /// Host-side probes for UITests — a class so escaping SDK hooks always mutate the same box.
    @StateObject private var hostProbe = HostProbe()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diverge Sample")
                    .font(.largeTitle)
                    .foregroundColor(Self.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(.h1)

                Text("Paste a visitor JWT, pick a backend, then open the chat.")
                    .font(.body)
                    .foregroundColor(Self.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("xcconfig: \(SampleConfig.environmentName) — \(SampleConfig.apiBaseURL.absoluteString)")
                    .font(.footnote)
                    .foregroundColor(Self.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Build configuration \(SampleConfig.environmentName)")

                Picker("Backend", selection: $backend) {
                    ForEach(Backend.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Backend")

                Text(self.backend.footnote)
                    .font(.footnote)
                    .foregroundColor(Self.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Appearance", selection: $appearance) {
                    Text("System").tag(AIChat.Appearance.system)
                    Text("Light").tag(AIChat.Appearance.light)
                    Text("Dark").tag(AIChat.Appearance.dark)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Appearance")

                TextField("Session token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .frame(minHeight: 48)
                    .accessibilityLabel("Session token")
                    .accessibilityHint("Demo token only. Do not use production secrets.")

                TextField("Page / URL (optional)", text: $page)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .frame(minHeight: 48)
                    .accessibilityLabel("Page or URL")
                    .accessibilityHint("Matched as a substring against start-prompt url_pattern. Example: /products or https://shop.example.com/products/123")

                Button("Open chat") {
                    self.openChat()
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
        // Swipe-to-dismiss would skip the SDK close path. Close is the path that dismisses.
        .sheet(item: self.$session) { session in
            session.chat.makeView()
                .interactiveDismissDisabled()
                .safeAreaInset(edge: .top) {
                    // Visible while the sheet is up so UITests can observe host hooks.
                    VStack(alignment: .leading, spacing: 4) {
                        if let lastOpenedURL = hostProbe.lastOpenedURL {
                            Text("Opened: \(lastOpenedURL)")
                                .font(.caption2)
                                .accessibilityIdentifier("sample.lastOpenedURL")
                        }
                        if let lastAddedProduct = hostProbe.lastAddedProduct {
                            Text("Added to cart: \(lastAddedProduct)")
                                .font(.caption2)
                                .accessibilityIdentifier("sample.lastAddedProduct")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                }
        }
        .onAppear { self.applyLaunchEnvironment() }
    }

    /// UITest / stand-in hooks: `SAMPLE_AUTO_TOKEN` opens the chat immediately;
    /// `SAMPLE_FLOW` selects ``AIChat/ConversationFlow`` (`topDown` / `bottomUp`);
    /// `SAMPLE_APPEARANCE` locks the palette (`system` / `light` / `dark`);
    /// `SAMPLE_PAGE` seeds the page field for start-prompt `url_pattern` matching;
    /// `SAMPLE_ATTACHMENTS=disabled` hides composer attach and upload-prompt cards;
    /// `SAMPLE_STANDIN=1` lets Reset POST `/__control` (in-memory stand-in history only);
    /// otherwise Reset needs `SAMPLE_CHATBOT_API_KEY` for `POST /api/v1/chat/auth/reset`.
    private func applyLaunchEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if env["SAMPLE_FLOW"] == "bottomUp" {
            self.conversationFlow = .bottomUp
        }
        switch env["SAMPLE_APPEARANCE"] {
        case "light": self.appearance = .light
        case "dark": self.appearance = .dark
        case "system": self.appearance = .system
        default: break
        }
        if env["SAMPLE_ATTACHMENTS"] == "disabled" {
            self.attachments = .disabled
        }
        if let page = env["SAMPLE_PAGE"], !page.isEmpty {
            self.page = page
        }
        if let auto = env["SAMPLE_AUTO_TOKEN"], !auto.isEmpty {
            self.token = auto
            self.backend = .local
            self.openChat()
        }
    }

    private var configurationIdentity: String {
        "\(self.token)|\(self.backend.rawValue)|\(String(describing: self.conversationFlow))|\(String(describing: self.appearance))|\(self.page)|\(String(describing: self.attachments))"
    }

    private func openChat() {
        if self.chat == nil || self.chatBoundTo != self.configurationIdentity {
            let probe = self.hostProbe
            probe.visitorToken = self.token
            self.chat = AIChat(Self.configuration(
                token: token,
                apiBaseURL: self.backend.apiBaseURL,
                conversationFlow: self.conversationFlow,
                appearance: self.appearance,
                attachments: self.attachments,
                page: self.page,
                onClose: { self.session = nil },
                onOpenLink: { url in
                    Task { @MainActor in
                        probe.lastOpenedURL = url.absoluteString
                    }
                    // Stand-in UITests observe the probe without leaving the app.
                    if ProcessInfo.processInfo.environment["SAMPLE_STANDIN"] != "1" {
                        UIApplication.shared.open(url)
                    }
                },
                onAddToCart: { selection in
                    let line = "\(selection.title) · \(selection.sku)"
                    Task { @MainActor in
                        probe.lastAddedProduct = line
                    }
                },
                probe: probe
            ))
            self.chatBoundTo = self.configurationIdentity
        }
        guard let chat else { return }
        self.session = ChatSession(chat: chat)
    }
}

// MARK: - SDK configuration

private extension ContentView {

    /// Token minting and data lifecycle stay with the host; the SDK only calls back for them.
    private static func configuration(
        token: String,
        apiBaseURL: URL,
        conversationFlow: AIChat.ConversationFlow,
        appearance: AIChat.Appearance,
        attachments: AIChat.Attachments,
        page: String,
        onClose: @escaping () -> Void,
        onOpenLink: @escaping (URL) -> Void,
        onAddToCart: @escaping @MainActor (AIChat.ProductSelection) -> Void,
        probe: HostProbe
    ) -> AIChat.Configuration {
        .init(
            tokenProvider: {
                let latest = probe.visitorToken
                return latest.isEmpty ? token : latest
            },
            resetConversation: {
                let current = probe.visitorToken.isEmpty ? token : probe.visitorToken
                let newToken = try await SampleVisitorReset.freshToken(
                    currentVisitorToken: current,
                    apiBaseURL: apiBaseURL
                )
                await MainActor.run { probe.visitorToken = newToken }
                return newToken
            },
            deleteData: {},
            contextProvider: {
                let trimmed = page.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            },
            onOpenLink: onOpenLink,
            onClose: onClose,
            onAddToCart: onAddToCart,
            conversationFlow: conversationFlow,
            apiBaseURL: apiBaseURL,
            attachments: attachments,
            appearance: appearance
        )
    }
}
