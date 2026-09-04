//
//  ChatView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import AIConversationEngine

/// The SDK's main screen — the chat UI returned by `AIChat.makeView()`.
struct ChatView: View {

    private let viewModel: ViewModel

    @Environment(\.openURL) private var openURL
    @FocusState private var inputFocused: Bool

    @State private var showSessionEndedAlert = false
    @State private var privacyDestination: PrivacyDataDestination?
    @State private var isLoading = false

    private var appearance: ChatAppearance {
        self.viewModel.appearance ?? .default
    }

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        self.content
            .modifier(LoadingOverlay(isLoading: self.isLoading))
            .task { await self.viewModel.start() }
            .environment(\.appearance, self.appearance)
            .environment(\.imageLoader, self.viewModel.imageLoader)
    }
}

// MARK: - Phases

private extension ChatView {

    @ViewBuilder
    var content: some View {
        switch self.viewModel.phase {
        case .loading: self.loadingView
        case .ready: self.readyView
        case .failed: self.failedView
        }
    }

    var loadingView: some View {
        ProgressView()
            .tint(self.appearance.theme.accent)
    }

    var readyView: some View {
        self.chatWindow
            .modifier(
                PrivacyDataSheetModifier(
                    destination: self.$privacyDestination,
                    onOpenPrivacy: {
                        if let url = self.viewModel.privacyPolicyURL {
                            self.openURL(url)
                        }
                    },
                    onDeleteData: { try await self.viewModel.delete() }
                )
            )
            .alert(L10n.sessionEndedTitle.string, isPresented: self.$showSessionEndedAlert) {
                Button(L10n.sessionEndedDismiss.string, role: .cancel) { } // NO-OP
            } message: {
                Text(L10n.sessionEndedMessage)
            }
    }

    var failedView: some View {
        BootstrapErrorView(
            onRetry: {
                Task { await self.viewModel.start() }
            }
        )
    }
}

// MARK: - Chat window

private extension ChatView {

    var chatWindow: some View {
        NavigationStack {
            Group {
                if let snapshot = self.viewModel.snapshot {
                    self.chat(from: snapshot)
                }
            }
            .navigationTitle(self.viewModel.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { self.resetToolbarItem }
            .safeAreaInset(edge: .bottom) { self.inputBar }
        }
        .safeAreaInset(edge: .top) { self.topNotice }
        .background(self.appearance.theme.background)
        .animation(.default, value: self.viewModel.notice)
        .onChange(of: self.inputFocused) { _, focused in
            if focused, self.viewModel.notice?.edge == .bottom {
                self.viewModel.dismissNotice()
            }
        }
    }

    var resetToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                self.reset()
            } label: {
                ChatAppearance.Symbol.reset
            }
            .disabled(self.viewModel.snapshot?.streamingTurnID != nil)
        }
    }

    func reset() {
        Task {
            self.isLoading = true
            await self.viewModel.reset()
            self.isLoading = false
        }
    }

    var inputBar: some View {
        self.chatInput
            .background(alignment: .top) {
                // A permanent wrapper ensures the alignment guide is never dropped
                VStack {
                    self.bottomNotice
                }
                // Align the bottom of VStack to the top of the chatInput
                .alignmentGuide(.top) { $0[.bottom] }
            }
    }

    @ViewBuilder
    var bottomNotice: some View {
        if let notice = self.viewModel.notice, notice.edge == .bottom {
            self.noticeBar(notice.message)
                .padding(.bottom, self.appearance.spacing.units(2))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    var topNotice: some View {
        if let notice = self.viewModel.notice, notice.edge == .top {
            self.noticeBar(notice.message)
                .transition(.move(edge: .top))
        }
    }

    func noticeBar(_ message: String) -> some View {
        NoticeBar(
            icon: ChatAppearance.Symbol.notice,
            message: message
        )
        .padding(.horizontal, self.appearance.spacing.units(4))
    }
}

// MARK: - Conversation

private extension ChatView {

    func chat(from snapshot: ConversationSnapshot) -> some View {
        self.conversationList(from: snapshot)
            .modifier(
                DismissKeyboardOnTap(
                    isActive: self.inputFocused,
                    onDismiss: {
                        self.inputFocused = false
                        self.viewModel.dismissNotice()
                    })
            )
    }

    /// layout whichever flow is configured.
    @ViewBuilder
    func conversationList(from snapshot: ConversationSnapshot) -> some View {
        /// The `List`-backed flows don't perform on macOS, so the Mac stays on the `ScrollView`-backed
#if os(macOS)
        ConversationView(
            snapshot: snapshot,
            isInputFocused: self.inputFocused,
            onLoadOlder: self.loadOlder,
            content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
            header: { self.chatHeader }
        )
        .equatable()
#else
        switch self.viewModel.conversationFlow {
        case .topDown:
            ConversationTopFlowingList(
                snapshot: snapshot,
                isInputFocused: self.inputFocused,
                onLoadOlder: self.loadOlder,
                content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
                header: { self.chatHeader }
            )
            .equatable()

        case .bottomUp:
            ConversationBottomFlowingList(
                snapshot: snapshot,
                isInputFocused: self.inputFocused,
                onLoadOlder: self.loadOlder,
                content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
                header: { self.chatHeader }
            )
            .equatable()
        }
#endif
    }

    @ViewBuilder
    func turnView(for turn: Identified<ConversationSnapshot.Turn>, streamingTurnID: UUID?) -> some View {
        switch turn.model {
        case .bot(let responses):
            self.botTurn(responses, isStreaming: turn.id == streamingTurnID)

        case .user(let bubbles):
            self.userTurn(bubbles)
        }
    }

    var chatHeader: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(6)) {
            if let logo = self.viewModel.logo {
                logo.image
                    .resizable()
                    .scaledToFit()
                    .frame(height: self.appearance.spacing.units(10))
                    .frame(maxWidth: .infinity, alignment: logo.alignment)
            }

            if let subtitle = self.viewModel.subtitle {
                ChatHeader(subtitle: subtitle)
            }
        }
    }

    /// Requests the next older page; a failure means the session is gone, so surface the ended alert.
    func loadOlder() async {
        do {
            try await self.viewModel.loadOlder()
        } catch {
            self.showSessionEndedAlert = true
        }
    }
}

// MARK: - Turn rendering

private extension ChatView {

    func botTurn(_ responses: [ChatResponse], isStreaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(responses.enumerated()), id: \.offset) { index, response in
                self.botResponse(
                    response,
                    // Only the last bubble is the one being generated, animate border/typewrite just that.
                    isStreaming: isStreaming && index == responses.count - 1,
                    isFirstResponse: index == 0,
                    isLastResponse: index == responses.count - 1 && !isStreaming
                )
            }
        }
    }

    @ViewBuilder
    func botResponse(
        _ response: ChatResponse,
        isStreaming: Bool,
        isFirstResponse: Bool,
        isLastResponse: Bool
    ) -> some View {
        switch response {
        case .text(let text):
            self.textResponse(text, isStreaming: isStreaming)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .placeholder(let text):
            self.placeholderTextResponse(text, isStreaming: isStreaming)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .products(let cards):
            ProductGridView(cards: cards)
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .table(let content):
            TableView(content: content)
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))
        }
    }

    func placeholderTextResponse(_ text: AttributedString, isStreaming: Bool) -> some View {
        BotBubble(text: text)
            .modifier(WaveEffect())
            .modifier(ThinkingBorderEffect(isActive: isStreaming, shape: Rectangle()))
    }

    func textResponse(_ text: AttributedString, isStreaming: Bool) -> some View {
        BotBubble(text: text)
            .modifier(TypewriterEffect(text: text, isActive: isStreaming))
            .modifier(ThinkingBorderEffect(isActive: isStreaming, shape: Rectangle()))
    }

    func userTurn(_ bubbles: [AttributedString]) -> some View {
        VStack(alignment: .trailing, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(bubbles.enumerated()), id: \.offset) { _, text in
                UserBubble(text: text)
                    .modifier(RelativeWidth(0.70, alignment: .trailing))
            }
        }
    }
}

// MARK: - Input

private extension ChatView {

    var chatInput: some View {
        ChatInput(
            currentMessage: .init(
                get: { self.viewModel.currentMessage },
                set: { self.viewModel.currentMessage = $0 }
            ),
            placeholder: L10n.inputPlaceholder.string,
            leadingIcon: ChatAppearance.Symbol.privacy,
            onLeadingTap: { self.privacyDestination = .privacy },
            onSend: self.send,
            inputFocus: self.$inputFocused
        )
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding([.bottom, .top], self.appearance.spacing.units(3))
        .background {
            self.appearance.theme.background
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .contentShape(.rect)
        .geometryGroup()
    }

    /// Dismisses the keyboard and sends the current message; a failure means the session is gone.
    func send() {
        self.inputFocused = false
        Task {
            do {
                try await self.viewModel.send()
            } catch {
                self.showSessionEndedAlert = true
            }
        }
    }
}
