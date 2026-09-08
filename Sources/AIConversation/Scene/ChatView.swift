//
//  ChatView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import PhotosUI
import AIConversationEngine

/// The SDK's main screen — the chat UI returned by `AIChat.makeView()`.
struct ChatView: View {

    let viewModel: ViewModel

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @FocusState var inputFocused: Bool
    /// The focused form text field (`"<partId>/<key>"`), if any. Owned here so one keyboard
    /// "Done" bar serves every form and the tap-to-dismiss overlay knows the keyboard is up.
    @FocusState var focusedFormField: String?
    /// Feedback field on the rating overlay. The overlay sits outside `NavigationStack`, so it
    /// owns a matching `form.done` bar; this binding lets Close / Skip dismiss the keyboard too.
    @FocusState var ratingFeedbackFocused: Bool

    @State var showSessionEndedAlert = false
    @State private var showLeaveLivechatConfirm = false
    @State private var privacyDestination: PrivacyDataDestination?
    @State var ratingSheet: RatingSheetToken?
    @State private var isLoading = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    /// Where the *next* pick lands. Set before presenting and deliberately **not** cleared on
    /// dismissal: the picker updates `selection` and flips `isPresented` in the same gesture and
    /// SwiftUI does not promise the order, so routing state must outlive presentation state.
    @State private var photoDestination: PhotoDestination = .composer
    /// Measured height of the overlaid composer so the list can keep the last turn above it.
    @State private var composerHeight: CGFloat = 0

    /// Where a photo pick should land — composer chip, a form file field, or a ticket attachment.
    enum PhotoDestination: Equatable {
        case composer
        case formField(partID: String, key: String)
        case ticketAttachment(partID: String)
        case imageUpload(RequestImageUpload)
    }

    private var appearance: ChatAppearance {
        let base = self.viewModel.appearance ?? .default
        return base.with(colorScheme: self.viewModel.resolvedScheme(environment: self.colorScheme))
    }

    /// Keyboard / pickers match the painted palette. Unset until ready so loading stays
    /// on the environment (no forced-light flash, no forced-dark chrome on a cloned theme).
    private var preferredChrome: ColorScheme? {
        guard self.viewModel.phase == .ready else { return nil }
        return self.viewModel.preferredColorScheme(for: self.appearance)
    }

    /// The one way to open the picker: fix the route, then present.
    private func pickPhoto(for destination: PhotoDestination) {
        self.photoDestination = destination
        self.isPhotoPickerPresented = true
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
            .preferredColorScheme(self.preferredChrome)
            .photosPicker(
                isPresented: self.$isPhotoPickerPresented,
                selection: self.$photoPickerItem,
                matching: .images
            )
            .onChange(of: self.photoPickerItem) { _, item in
                guard let item else { return }
                self.photoPickerItem = nil
                let destination = self.photoDestination
                Task { await self.ingest(item, destination: destination) }
            }
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
            .tint(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
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
                    onExportData: { try await self.viewModel.exportMyData() },
                    onDiscardExport: { self.viewModel.discardExportFile() },
                    onDeleteData: { try await self.viewModel.delete() },
                    onSessionEnded: { self.showSessionEndedAlert = true }
                )
            )
            // Overlay card — not a nested `.sheet`. Sample already presents ChatView in a
            // sheet; a second sheet(item:) never surfaces on iOS in that host.
            .modifier(
                ConversationRatingSheetModifier(
                    token: self.$ratingSheet,
                    feedbackFocus: self.$ratingFeedbackFocused,
                    onSubmit: { score, feedback in
                        self.submitRating(score: score, feedback: feedback)
                    },
                    onSkip: {
                        self.skipRating()
                    },
                    onSkipFeedback: { score in
                        self.submitRating(score: score, feedback: nil)
                    }
                )
            )
            .onChange(of: self.ratingSheet == nil) { _, isNil in
                if isNil {
                    self.viewModel.endRating()
                }
            }
            .onChange(of: self.viewModel.livechatCSATPending) { _, pending in
                if pending {
                    self.presentLivechatCSATIfNeeded()
                }
            }
            .onChange(of: self.viewModel.isLivechatInSession) { _, inSession in
                if inSession {
                    self.dismissLivechatCSATOverlayIfPresented()
                }
            }
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
#if os(iOS)
            .toolbarBackground(self.appearance.theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
            .toolbar {
                if self.viewModel.showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            self.requestClose()
                        } label: {
                            HeaderToolbarIcon(symbol: ChatAppearance.Symbol.close)
                        }
                        .accessibilityLabel(L10n.ratingClose.string)
                        .accessibilityIdentifier("rating.close")
                    }
                }
                self.resetToolbarItem
                self.livechatToolbarItem
            }
        }
        // Input sits outside the NavigationStack. The conversation List can collapse
        // in-stack `safeAreaInset`s to zero height on some iOS hosts; chrome outside
        // the stack stays visible.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if self.viewModel.isAgentTyping {
                    AgentTypingIndicator(agentName: self.viewModel.livechat.agentDisplayName)
                }
                self.waitingFormSaveChrome
                self.inputBar
            }
            .measuringComposerHeight(self.$composerHeight)
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                self.topNotice
                if !self.viewModel.visibleBanners.isEmpty {
                    ChatBannerStrip(
                        banners: self.viewModel.visibleBanners,
                        onDismiss: { self.viewModel.dismissBanner($0) }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: self.viewModel.visibleBanners.map(\.contentFingerprint))
        }
        .background(self.appearance.theme.background)
        .animation(.default, value: self.viewModel.notice)
        .onChange(of: self.inputFocused) { _, focused in
            if focused, self.viewModel.notice?.edge == .bottom {
                self.viewModel.dismissNotice()
            }
        }
        .onChange(of: self.viewModel.currentMessage) { _, newValue in
            self.viewModel.visitorTypingChanged(
                isEmpty: newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .onChange(of: self.scenePhase) { _, phase in
            self.viewModel.setLivechatSceneActive(phase == .active)
        }
        .onAppear { self.viewModel.setLivechatVisible(true) }
        .onDisappear { self.viewModel.setLivechatVisible(false) }
        .onChange(of: self.viewModel.livechatSessionEnded) { _, ended in
            if ended { self.showSessionEndedAlert = true }
        }
        .onChange(of: self.viewModel.sessionEnded) { _, ended in
            if ended { self.showSessionEndedAlert = true }
        }
        .confirmationDialog(
            L10n.livechatLeaveConfirmTitle.string,
            isPresented: self.$showLeaveLivechatConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.livechatLeaveConfirmAction.string, role: .destructive) {
                self.confirmLeaveLivechat()
            }
            Button(L10n.deleteCancel.string, role: .cancel) {}
        } message: {
            Text(L10n.livechatLeaveConfirmMessage.string)
        }
    }

    func confirmLeaveLivechat() {
        Task {
            await self.withSessionAlert {
                try await self.viewModel.closeLivechat(reason: "visitor_left")
            }
        }
    }

    var resetToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                self.reset()
            } label: {
                HeaderToolbarIcon(symbol: ChatAppearance.Symbol.reset)
            }
            .disabled(self.viewModel.isStreaming)
            .accessibilityLabel("Reset conversation")
            .accessibilityIdentifier("chat.reset")
        }
    }

    @ToolbarContentBuilder
    var livechatToolbarItem: some ToolbarContent {
        if self.viewModel.livechatEnabled, self.viewModel.showLivechatLogo || self.viewModel.isLivechatInSession {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    self.handleLivechatToolbarTap()
                } label: {
                    HeaderToolbarIcon(symbol: ChatAppearance.Symbol.person)
                }
                // Keep tappable while offline so we can show the top notice (no hover
                // tooltips on iOS). Visual mute replaces `.disabled`.
                .opacity(
                    self.viewModel.livechatAvailable || self.viewModel.isLivechatInSession
                        ? 1
                        : 0.4
                )
                .disabled(self.viewModel.isLivechatCSATBlockingHandover)
                .accessibilityLabel(
                    self.viewModel.isLivechatInSession
                        ? L10n.livechatToolbarLeave.string
                        : L10n.livechatToolbarRequest.string
                )
                .accessibilityValue(
                    self.viewModel.livechatAvailable || self.viewModel.isLivechatInSession
                        ? L10n.livechatA11yAvailable.string
                        : L10n.livechatA11yOffline.string
                )
                .accessibilityIdentifier("livechat.toolbar")
            }
        }
    }

    func handleLivechatToolbarTap() {
        if self.viewModel.isLivechatInSession {
            self.showLeaveLivechatConfirm = true
            return
        }
        if self.viewModel.isLivechatCSATBlockingHandover {
            return
        }
        if !self.viewModel.livechatAvailable {
            self.viewModel.presentNotice(Notice(
                edge: .top,
                message: L10n.livechatOffline.string,
                autoDismiss: .seconds(4)
            ))
            return
        }
        Task {
            await self.withSessionAlert {
                try await self.viewModel.requestHandover(
                    source: LivechatHandoverRequest.manualButtonSource
                )
            }
        }
    }

    /// Close: offer the rating prompt when appropriate, otherwise hand off to the host immediately.
    // (requestClose / skipRating / submitRating live in ChatView+Rating.swift)

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
            // A form field keeps the keyboard up over the card's own controls; a drag on the
            // list dismisses it, and the bar above the keyboard offers an explicit way out.
            .scrollDismissesKeyboard(.interactively)
            .modifier(
                DismissKeyboardOnTap(
                    isActive: self.inputFocused,
                    onDismiss: {
                        self.inputFocused = false
                        self.viewModel.dismissNotice()
                    })
            )
#if os(iOS)
            // Only while a form field is focused — a permanent `.keyboard` group next to the
            // close ToolbarItem blanks the NavigationStack when ChatView is hosted in a sheet.
            // Rating feedback owns a matching bar on the overlay (outside this stack).
            .toolbar {
                if self.focusedFormField != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L10n.formDone.string) { self.focusedFormField = nil }
                            .accessibilityIdentifier("form.done")
                    }
                }
            }
#endif
    }

    /// layout whichever flow is configured.
    @ViewBuilder
    func conversationList(from snapshot: ConversationSnapshot) -> some View {
        /// The `List`-backed flows don't perform on macOS, so the Mac stays on the `ScrollView`-backed
#if os(macOS)
        ConversationView(
            snapshot: snapshot,
            isInputFocused: self.inputFocused,
            composerClearance: self.composerHeight,
            onLoadOlder: self.loadOlder,
            content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
            header: { self.chatHeader },
            footer: { self.conversationEdgeChrome },
            showsFooter: self.showsConversationEdgeChrome
        )
        .equatable()
#else
        switch self.viewModel.conversationFlow {
        case .topDown:
            ConversationTopFlowingList(
                snapshot: snapshot,
                isInputFocused: self.inputFocused,
                composerClearance: self.composerHeight,
                onLoadOlder: self.loadOlder,
                content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
                header: { self.chatHeader },
                footer: { self.conversationEdgeChrome },
                showsFooter: self.showsConversationEdgeChrome
            )
            .equatable()

        case .bottomUp:
            ConversationBottomFlowingList(
                snapshot: snapshot,
                isInputFocused: self.inputFocused,
                composerClearance: self.composerHeight,
                onLoadOlder: self.loadOlder,
                content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
                header: { self.chatHeader },
                footer: { self.conversationEdgeChrome },
                showsFooter: self.showsConversationEdgeChrome
            )
            .equatable()
        }
#endif
    }

    @ViewBuilder
    func turnView(for turn: Identified<ConversationSnapshot.Turn>, streamingTurnID: UUID?) -> some View {
        switch turn.model {
        case .bot(let responses):
            self.botTurn(
                responses,
                isStreaming: turn.id == streamingTurnID,
                isLatestBotTurn: self.viewModel.isFormEditable(inBotTurn: turn.id),
                agent: nil
            )

        case .agent(let agent, let responses):
            self.botTurn(
                responses,
                isStreaming: false,
                isLatestBotTurn: self.viewModel.isFormEditable(inBotTurn: turn.id),
                agent: agent
            )

        case .user(let bubbles):
            self.userTurn(bubbles)

        case .note(let note):
            LivechatNoteRow(note: note)

        case .system(let responses):
            SystemNoteRow(responses: responses)
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

    /// Requests the next older page and reports how it went. A throw means the session is gone,
    /// so surface the ended alert — nothing was prepended, and there is nothing left to retry.
    func loadOlder() async -> HistoryLoadOutcome {
        var outcome = HistoryLoadOutcome.nothing
        await self.withSessionAlert { outcome = try await self.viewModel.loadOlder() }
        return outcome
    }
}

// MARK: - Turn rendering

private extension ChatView {

    static func agentName(_ agent: LivechatAgent) -> String {
        let name = agent.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? L10n.livechatAgentFallback.string : name
    }

    func botTurn(
        _ responses: [ChatResponse],
        isStreaming: Bool,
        isLatestBotTurn: Bool,
        agent: LivechatAgent?
    ) -> some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            if let agent {
                Text(Self.agentName(agent))
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.secondaryText)
                    .accessibilityIdentifier("livechat.agentName")
            }
            ForEach(Array(responses.enumerated()), id: \.offset) { index, response in
                self.botResponse(
                    response,
                    // Only the last bubble is the one being generated, animate border/typewrite just that.
                    isStreaming: isStreaming && index == responses.count - 1,
                    isFirstResponse: index == 0,
                    isLastResponse: index == responses.count - 1 && !isStreaming,
                    isLatestBotTurn: isLatestBotTurn,
                    agent: agent
                )
            }
        }
    }

    @ViewBuilder
    func botResponse(
        _ response: ChatResponse,
        isStreaming: Bool,
        isFirstResponse: Bool,
        isLastResponse: Bool,
        isLatestBotTurn: Bool,
        agent: LivechatAgent?
    ) -> some View {
        switch response {
        case .text(let text):
            self.textResponse(text, isStreaming: isStreaming)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: agent == nil ? self.viewModel.avatar : nil, edge: .leading))

        case .placeholder(let text):
            self.placeholderTextResponse(text, isStreaming: isStreaming)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .products(let cards):
            ProductGridView(
                cards: cards,
                openLabel: self.viewModel.productOpenLabel,
                onAddToCart: self.viewModel.productAddToCart
            )
            .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
            .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .suggestions(let cards):
            SuggestionGridView(cards: cards, onSelect: { self.send(prompt: $0) })
                .disabled(self.viewModel.isStreaming)
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .quickReplies(let replies):
            QuickRepliesView(replies: replies, onSelect: { self.send(prompt: $0) })
                .disabled(self.viewModel.isStreaming || !isLatestBotTurn)
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .requestImageUpload(let marker):
            // Only reaches the view when the host offers attachments — the provider drops the
            // marker at ingestion otherwise, so a marker-only message leaves no empty row.
            ImageUploadPromptView {
                self.pickPhoto(for: .imageUpload(marker))
            }
                .disabled(!self.viewModel.canAttachConsideringLivechat)
                .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
                .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .requestHumanAgent(let marker):
            HumanAgentPromptView {
                Task {
                    await self.withSessionAlert {
                        try await self.viewModel.requestHandover(
                            source: LivechatHandoverRequest.assistantMarkerSource,
                            partId: marker.partId
                        )
                    }
                }
            }
            .disabled(!self.viewModel.livechatAvailable || self.viewModel.isLivechatInSession)
            .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
            .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .form(let form):
            let model = self.viewModel.formModel(for: form)
            ConversationFormView(
                model: model,
                isEditable: isLatestBotTurn,
                offersAttachments: self.viewModel.offersAttachments,
                isBusy: self.viewModel.isStreaming || self.viewModel.isEncodingAttachment,
                focus: self.$focusedFormField,
                onSubmit: {
                    self.inputFocused = false
                    self.focusedFormField = nil
                    Task {
                        await self.withSessionAlert {
                            try await self.viewModel.submitForm(partId: form.partId)
                        }
                    }
                },
                onPickFile: { key in
                    self.pickPhoto(for: .formField(partID: form.partId, key: key))
                },
                onPickTicketAttachment: {
                    self.pickPhoto(for: .ticketAttachment(partID: form.partId))
                }
            )
            .padding(.bottom, isLastResponse ? 0 : self.appearance.spacing.units(9))
            .padding(.top, isFirstResponse ? 0 : self.appearance.spacing.units(9))

        case .image(let image):
            MessageImageView(image: image)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: agent == nil ? self.viewModel.avatar : nil, edge: .leading))

        case .file(let file):
            MessageFileView(file: file)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: agent == nil ? self.viewModel.avatar : nil, edge: .leading))

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

    func userTurn(_ contents: [UserContent]) -> some View {
        VStack(alignment: .trailing, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(contents.enumerated()), id: \.offset) { _, content in
                self.userContent(content)
            }
        }
    }

    @ViewBuilder
    func userContent(_ content: UserContent) -> some View {
        switch content {
        case .text(let text):
            UserBubble(text: text)
                .modifier(RelativeWidth(0.70, alignment: .trailing))

        case .image(let image):
            MessageImageView(image: image)
                .modifier(RelativeWidth(0.70, alignment: .trailing))

        case .file(let file):
            MessageFileView(file: file)
                .modifier(RelativeWidth(0.70, alignment: .trailing))
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
            pendingAttachments: .init(
                get: { self.viewModel.pendingAttachments },
                set: { self.viewModel.pendingAttachments = $0 }
            ),
            placeholder: self.viewModel.inputPlaceholder,
            leadingIcon: ChatAppearance.Symbol.privacy,
            showsAttachButton: self.viewModel.offersAttachments,
            canAttach: self.viewModel.canAttachConsideringLivechat,
            isEncodingAttachment: self.viewModel.isEncodingAttachment,
            onLeadingTap: { self.privacyDestination = .privacy },
            onAttach: { self.pickPhoto(for: .composer) },
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

    /// Loads the picked photo bytes and routes them to the composer or a form field.
    func ingest(_ item: PhotosPickerItem, destination: PhotoDestination) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            self.viewModel.presentAttachmentFailure()
            return
        }
        switch destination {
        case .composer:
            await self.viewModel.ingestPickedPhoto(data)

        case .imageUpload(let marker):
            await self.viewModel.ingestPromptPhoto(data, marker: marker)

        case .formField(let partID, let key):
            // Custom-form files share the `/actions` `Attachment` 2 MiB decoded cap.
            guard let file = await self.viewModel.ingestFormPhoto(
                data,
                maxBytes: OutgoingAttachment.maxActionDecodedBytes,
                filename: "\(key).jpg"
            ) else { return }
            self.viewModel.formModel(forPartId: partID)?.setFile(file, for: key)

        case .ticketAttachment(let partID):
            let maxBytes = self.viewModel.formModel(forPartId: partID)?.form.maxAttachmentSizeBytes
                ?? OutgoingAttachment.maxActionDecodedBytes
            guard let file = await self.viewModel.ingestFormPhoto(
                data,
                maxBytes: maxBytes,
                filename: OutgoingAttachment.fallbackFilename
            ) else { return }
            self.viewModel.formModel(forPartId: partID)?.setTicketAttachment(file)
        }
    }
}

extension ChatView {

    /// Dismisses the keyboard and sends the current message; a failure means the session is gone.
    func send() {
        self.inputFocused = false
        Task { await self.withSessionAlert { try await self.viewModel.send() } }
    }

    /// Dismisses the keyboard and sends a suggestion-card or start-prompt chip's text; a failure
    /// means the session is gone.
    func send(prompt: String) {
        self.inputFocused = false
        Task { await self.withSessionAlert { try await self.viewModel.send(prompt: prompt) } }
    }

    /// Runs a session-bound action; surfaces the ended alert when the session is gone.
    func withSessionAlert(_ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            self.showSessionEndedAlert = true
        }
    }
}
