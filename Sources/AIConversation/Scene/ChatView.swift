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

    /// Held as state so a host re-render, which builds a new `ChatView` and a new model, keeps the
    /// model this view already bootstrapped. A new presentation starts a model of its own.
    @State private var viewModel: ViewModel

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var inputFocused: Bool
    @FocusState private var focusedFormField: String?

    @State private var showSessionEndedAlert = false
    @State private var privacyDestination: PrivacyDataDestination?
    @State private var isLoading = false

    private var appearance: ChatAppearance {
        self.viewModel.appearance ?? .default
    }

    init(viewModel: ViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .onChange(of: self.viewModel.backgroundSessionEnded) { _, ended in
                guard ended else { return }
                self.viewModel.backgroundSessionEnded = false
                self.showSessionEndedAlert = true
            }
            .sheet(isPresented: self.isLivechatRatingPresented) {
                if let model = self.viewModel.rating.model {
                    LivechatRatingView(
                        model: model,
                        onSubmit: { score, feedback in
                            Task { await self.viewModel.rating.submit(score: score, feedback: feedback) }
                        },
                        onSkip: { self.viewModel.rating.dismiss() }
                    )
                    .environment(\.appearance, self.appearance)
                }
            }
            .sheet(
                isPresented: self.isConversationRatingPresented,
                onDismiss: { self.viewModel.ratingDidDismiss() },
                content: {
                    if let model = self.viewModel.conversationRating.model {
                        LivechatRatingView(
                            model: model,
                            onSubmit: { score, feedback in
                                Task { await self.viewModel.submitRating(score: score, feedback: feedback) }
                            },
                            onSkip: { self.viewModel.skipRating() }
                        )
                        .environment(\.appearance, self.appearance)
                    }
                }
            )
            .onChange(of: self.viewModel.livechatSessionEnded) { _, ended in
                guard ended else { return }
                self.viewModel.livechatSessionEnded = false
                self.showSessionEndedAlert = true
            }
            .onChange(of: self.scenePhase) { _, phase in
                Task { await self.viewModel.setSceneActive(phase == .active) }
            }
            .onAppear { Task { await self.viewModel.setVisible(true) } }
            .onDisappear { Task { await self.viewModel.setVisible(false) } }
    }

    /// Livechat CSAT is up while its controller holds a draft; swiping it away skips.
    var isLivechatRatingPresented: Binding<Bool> {
        Binding(
            get: { self.viewModel.rating.model != nil },
            set: { isPresented in
                if !isPresented, self.viewModel.rating.model != nil {
                    self.viewModel.rating.dismiss()
                }
            }
        )
    }

    /// The conversation rating is up while its controller holds a draft; swiping it away skips.
    /// The host hears the close from the sheet's `onDismiss`, once the prompt has gone.
    var isConversationRatingPresented: Binding<Bool> {
        Binding(
            get: { self.viewModel.conversationRating.model != nil },
            set: { isPresented in
                if !isPresented, self.viewModel.conversationRating.model != nil {
                    self.viewModel.skipRating()
                }
            }
        )
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
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(self.viewModel.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if self.viewModel.showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            self.inputFocused = false
                            self.viewModel.close()
                        } label: {
                            ChatAppearance.Symbol.close
                        }
                        .accessibilityLabel(L10n.chatClose.string)
                        .accessibilityIdentifier("chat.close")
                    }
                }
                self.livechatToolbarItem
                self.resetToolbarItem
            }
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
            .disabled(self.viewModel.snapshot?.streamingTurnID != nil || self.viewModel.isLivechatBusy)
        }
    }

    @ToolbarContentBuilder
    var livechatToolbarItem: some ToolbarContent {
        if self.viewModel.livechatControl != .hidden {
            ToolbarItem(placement: .primaryAction) {
                LivechatControlButton(viewModel: self.viewModel)
            }
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
        VStack(spacing: 0) {
            if let model = self.viewModel.waitingForm.model {
                self.waitingFormCard(model)
                LivechatWaitingFormSaveChrome(model: model) {
                    Task { await self.viewModel.waitingForm.save() }
                }
            }
            if self.viewModel.isAgentTyping {
                AgentTypingIndicator(agentName: self.viewModel.livechatAgentName)
            }
            self.chatInput
        }
        .background(alignment: .top) {
            // A permanent wrapper ensures the alignment guide is never dropped
            VStack {
                self.bottomNotice
            }
            // Align the bottom of VStack to the top of the input bar, above the typing row
            .alignmentGuide(.top) { $0[.bottom] }
        }
    }

    /// The waiting-room card above the composer. One scroll view hugs the card up to a capped
    /// height and scrolls past it, so the save row and the composer stay on screen and the
    /// fields keep their identity, and their focus, as the card grows.
    func waitingFormCard(_ model: WaitingFormModel) -> some View {
        ScrollView {
            LivechatWaitingFormView(model: model, focus: self.$focusedFormField)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: self.appearance.spacing.units(48))
        .fixedSize(horizontal: false, vertical: true)
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
            self.botTurn(responses, turnID: turn.id, isStreaming: turn.id == streamingTurnID)

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

    func botTurn(_ responses: [ChatResponse], turnID: UUID, isStreaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(responses.enumerated()), id: \.offset) { index, response in
                self.botResponse(
                    response,
                    turnID: turnID,
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
        turnID: UUID,
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

        case .form(let form):
            if let model = self.viewModel.formModels[form.partId] {
                ConversationFormView(
                    model: model,
                    isEditable: self.viewModel.isFormEditable(inBotTurn: turnID),
                    // The whole turn, not just this bubble: the backend saves the form when the
                    // reply's stream ends, so a submit before then is rejected.
                    isBusy: self.viewModel.snapshot?.streamingTurnID == turnID,
                    focus: self.$focusedFormField,
                    onChange: { key, value in
                        self.viewModel.setFormValue(value, for: key, inForm: form.partId)
                    },
                    onSubmit: {
                        self.inputFocused = false
                        self.focusedFormField = nil
                        Task {
                            do {
                                try await self.viewModel.submitForm(partId: form.partId)
                            } catch {
                                self.showSessionEndedAlert = true
                            }
                        }
                    },
                    onReload: { self.viewModel.reloadFormDefinition(partId: form.partId) }
                )
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))
            }

        case .table(let content):
            TableView(content: content)
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .file(let file):
            MessageFileView(file: file, resolveURL: { await self.viewModel.url(toOpen: $0) })
                .modifier(RelativeWidth(0.70, alignment: .leading))

        case .requestHumanAgent(let marker):
            HumanAgentPromptView(viewModel: self.viewModel, partId: marker.partId, turnID: turnID)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .livechatNote(let note):
            LivechatNoteRow(note: note)

        case .systemNote(let text):
            NoteRow(text: text, identifier: "conversation.systemNote")
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

    func userTurn(_ bubbles: [UserContent]) -> some View {
        VStack(alignment: .trailing, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(bubbles.enumerated()), id: \.offset) { _, content in
                switch content {
                case .text(let text):
                    UserBubble(text: text)
                        .modifier(RelativeWidth(0.70, alignment: .trailing))
                case .attachment:
                    // Rendered by photo-upload-ui.
                    EmptyView()
                }
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
                set: { self.viewModel.editDraft($0) }
            ),
            placeholder: self.viewModel.inputPlaceholder,
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
