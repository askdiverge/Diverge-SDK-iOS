//
//  ChatView+ViewModel.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import AIConversationEngine

extension ChatView {

    /// Observable state for the main screen. Coordinates the chat service facade
    @MainActor
    @Observable
    final class ViewModel {

        enum Phase {
            case loading, ready, failed
        }

        private(set) var phase: Phase = .loading
        private(set) var appearance: ChatAppearance?

        private(set) var name = ""
        private(set) var subtitle: Subtitle?
        private(set) var privacyPolicyURL: URL?
        private(set) var avatar: Image?
        private(set) var logo: HeaderLogo?
        private(set) var notice: Notice?

        /// Livechat as `/config` describes it, and the session's status as the poller last saw it.
        private(set) var livechatConfig = LivechatConfig.serverDefaults
        private(set) var livechatStatus = LivechatState.Status.inactive
        /// A handover or close is in flight; the header control and reset wait for it.
        private(set) var isLivechatBusy = false
        /// Set when the poller sees the visitor session end (401). The view shows the session-ended
        /// alert and clears it.
        var livechatSessionEnded = false

        /// Shared loader for remote imagery injected into the view environment.
        @ObservationIgnored let imageLoader: ImageLoader
        @ObservationIgnored let conversationFlow: AIChat.ConversationFlow
        @ObservationIgnored private let service: ChatService
        @ObservationIgnored private let pageContext: @Sendable () async -> String?
        @ObservationIgnored private var provider: (any ChatProviding)?
        @ObservationIgnored private let submitAction: ActionSubmitter
        @ObservationIgnored private let fetchForm: FormFetcher
        @ObservationIgnored private let livechat: LivechatSession

        private(set) var snapshot: ConversationSnapshot?
        /// Drafts of the conversation's forms by `part_id`, created when a snapshot first brings
        /// the form so a draft survives list recycling.
        private(set) var formModels: [String: FormSubmissionModel] = [:]
        var currentMessage = ""

        /// Submits a marker-triggered action. Defaults to ``ChatService/submitAction``; tests
        /// inject a stub so form success / failure paths do not need a live network.
        typealias ActionSubmitter = @Sendable (SubmitActionRequest) async throws -> SubmitActionResponse

        /// Fetches a form definition. Defaults to ``ChatService/fetchForm``.
        typealias FormFetcher = @Sendable (String) async throws -> ChatFormDefinition

        init(
            service: ChatService,
            contextProvider: (@Sendable () async -> String?)?,
            conversationFlow: AIChat.ConversationFlow,
            submitAction: ActionSubmitter? = nil,
            fetchForm: FormFetcher? = nil,
            livechat: LivechatSession? = nil
        ) {
            self.service = service
            self.pageContext = { await contextProvider?() }
            self.conversationFlow = conversationFlow
            self.submitAction = submitAction ?? { request in
                try await service.submitAction(request)
            }
            self.fetchForm = fetchForm ?? { id in
                try await service.fetchForm(id: id)
            }
            self.livechat = livechat ?? LivechatSession(service: service)
            // Product/table imagery fills ~half-width, ~800px covers 3x.
            self.imageLoader = ImageLoader(maxPixelSize: 800) { try await service.fetchData($0) }
            self.observeLivechat()
        }

        /// Bootstraps once, then no-ops on re-entry
        /// (e.g. the view reappearing) so the live session survives.
        func start() async {
            guard self.provider == nil else { return }
            await self.bootstrap()
        }

        /// Config → provider → snapshot stream → first history page.
        /// A config failure is surfaced on `phase` (retry re-enters here),
        /// a history failure is non-fatal.
        private func bootstrap() async {
            self.phase = .loading

            do {
                let config = try await self.service.fetchConfig()
                self.avatar = await self.loadImage(config.display.avatar.url, maxPixelSize: 200)
                self.logo = await self.loadImage(config.theme.header.logo.url, maxPixelSize: 600)
                    .map { HeaderLogo(image: $0, alignment: config.theme.header.alignment) }
                let fontFamily = await FontLoader.loadFamily(
                    url: config.theme.font.ios.assetUrl,
                    sha256: config.theme.font.ios.sha256,
                    format: config.theme.font.ios.format,
                    fetch: { [service = self.service] in try await service.fetchData($0) }
                )
                self.appearance = ChatAppearance(config, fontFamily: fontFamily)
                self.name = config.display.name
                self.subtitle = config.display.subtitle.map { Subtitle($0) }
                self.privacyPolicyURL = config.display.privacyPolicyUrl

                let provider = ChatProvider(
                    service: self.service,
                    pageContext: self.pageContext,
                    welcomeMessage: config.display.welcomeMessage
                )

                self.provider = provider
                self.observe(provider)

                try? await provider.loadOlder()
                self.startLivechat(with: config.livechat)
                self.phase = .ready

            } catch {
                self.phase = .failed
            }
        }

        /// Sends a user message, to the agent while a livechat session is active and otherwise to the
        /// assistant. Recoverable failures (busy, retryable) bounce inline as a notice so the input
        /// stays stateless; a 401 ends the session and escapes as ``SessionEnded`` for the view to
        /// alert on.
        func send() async throws(SessionEnded) {
            if self.notice?.edge == .bottom { self.dismissNotice() }
            let text = self.currentMessage

            guard let provider = self.provider, !text.isEmpty else { return }

            do {
                self.currentMessage = ""
                try await self.deliver(text, via: provider)

            } catch {
                switch error {
                case .busy(.streaming):
                    self.currentMessage = text
                    self.present(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))

                case .busy(.operation):
                    break // NO-OP for now

                case .retry(popped: let lastMessage, body: let body):
                    self.currentMessage = lastMessage
                    self.present(Notice(edge: .bottom, message: body ?? L10n.noticeSendFailed.string, autoDismiss: nil))

                case .livechatInactive(popped: let lastMessage), .livechatActive(popped: let lastMessage):
                    // Livechat changed under the send; the next one goes where the refreshed state says.
                    self.currentMessage = lastMessage
                    self.present(Notice(edge: .bottom, message: L10n.noticeSendFailed.string, autoDismiss: nil))
                    await self.livechat.refresh()

                case .sessionExpired:
                    throw SessionEnded()
                }
            }
        }

        /// Whether a form card in the given bot turn may still be filled — only the newest bot
        /// turn's forms are actionable (the server rejects older `part_id`s).
        func isFormEditable(inBotTurn turnID: UUID) -> Bool {
            self.snapshot?.lastBotTurnID == turnID
        }

        /// Sets a text or dropdown answer on the draft of form `partId`.
        func setFormValue(_ value: String, for key: String, inForm partId: String) {
            self.formModels[partId]?.setValue(value, for: key)
        }

        /// Fetches the definition of a thin custom form again after the first fetch failed.
        func reloadFormDefinition(partId: String) {
            guard
                let model = self.formModels[partId], model.hydrationFailed,
                case .custom(let formId, _, _, _) = model.form.kind
            else { return }
            self.hydrateCustomForm(partId: partId, formId: formId)
        }

        /// Validates and submits the form identified by `partId`. Surfaces session expiry;
        /// other failures land on the form card. A no-op for unknown ids, drafts that fail
        /// validation, and forms already submitting or submitted.
        func submitForm(partId: String) async throws(SessionEnded) {
            guard let model = self.formModels[partId], !model.isSubmitting, !model.isSubmitted else { return }
            guard self.formModels[partId]?.validate() == true else { return }
            guard let request = model.buildRequest() else {
                self.formModels[partId]?.markFailed()
                return
            }
            guard self.formModels[partId]?.beginSubmitting() == true else { return }

            do {
                let response = try await self.submitAction(request)
                let text = FormSubmissionModel.confirmation(server: response.confirmationText, form: model.form)
                self.formModels[partId]?.markSubmitted(confirmation: text)
            } catch ChatServiceError.sessionExpired {
                self.formModels[partId]?.markFailed()
                throw SessionEnded()
            } catch ChatServiceError.validation(let message, let params) {
                self.formModels[partId]?.applyServerErrors(params: params, formMessage: message)
            } catch {
                self.formModels[partId]?.markFailed()
            }
        }

        /// Loads the next older page of history. A recoverable failure surfaces as a top notice;
        /// a 401 ends the session and escapes as ``SessionEnded`` for the view to alert on.
        func loadOlder() async throws(SessionEnded) {
            if self.notice?.edge == .top { self.dismissNotice() }

            do {
                try await self.provider?.loadOlder()

            } catch ChatServiceError.sessionExpired {
                throw SessionEnded()

            } catch {
                self.present(Notice(
                    edge: .top,
                    message: L10n.noticeHistoryLoadFailed.string,
                    autoDismiss: .seconds(4)
                ))
            }
        }

        /// Resets the conversation. An open livechat session is closed first, because nobody could
        /// close it once the visitor is replaced.
        func reset() async {
            guard !self.isLivechatBusy, await self.closeLivechatBeforeReset() else { return }
            do {
                try await self.provider?.reset()
            } catch {
                // A failed reset leaves the conversation, and its form drafts, as they were.
                return
            }
            self.formModels = [:]
            await self.livechat.teardown()
        }

        /// Request deletion of visitor data and end the session. Rethrows so the delete sheet can act on the
        /// hook's suspension point — success dismisses it, a failure leaves it open for the host.
        func delete() async throws(DeletionFailed) {
            do {
                try await self.provider?.delete()
            } catch {
                throw DeletionFailed()
            }
            self.formModels = [:]
            await self.livechat.teardown()
        }

        /// Test seam — attach a stub provider without bootstrapping `/config`.
        func attachProviderForTesting(_ provider: some ChatProviding) {
            self.provider = provider
            self.observe(provider)
        }

        /// Pre-loads a config image once, downsampled, so it isn't re-fetched during rendering.
        private func loadImage(_ url: URL?, maxPixelSize: CGFloat) async -> Image? {
            guard
                let url,
                let data = try? await self.service.fetchData(url)
            else {
                return nil
            }
            return RemoteImage.decode(data, maxPixelSize: maxPixelSize)
        }

        /// Mirrors the provider's latest-wins snapshots onto the main actor, preparing a draft for
        /// each form a snapshot brings before the view renders it.
        private func observe(_ provider: some ChatProviding) {
            let stream = provider.stream
            Task { [weak self] in
                for await snapshot in stream {
                    self?.prepareForms(in: snapshot)
                    self?.snapshot = snapshot
                }
            }
        }

        /// Creates a draft for each form `snapshot` brings for the first time. A thin custom
        /// `show_form` (no inline fields) fills in from `GET …/forms/{id}`.
        private func prepareForms(in snapshot: ConversationSnapshot) {
            for turn in snapshot.incoming {
                for case .form(let form) in turn.model where self.formModels[form.partId] == nil {
                    self.formModels[form.partId] = FormSubmissionModel(form: form)
                    if case .custom(let formId, _, _, _) = form.kind, form.fields.isEmpty {
                        self.hydrateCustomForm(partId: form.partId, formId: formId)
                    }
                }
            }
        }

        private func hydrateCustomForm(partId: String, formId: String) {
            self.formModels[partId]?.beginHydrating()
            Task { [weak self, fetchForm = self.fetchForm] in
                do {
                    let definition = try await fetchForm(formId)
                    self?.formModels[partId]?.applyHydratedDefinition(definition)
                } catch {
                    self?.formModels[partId]?.failHydrating()
                }
            }
        }

        private func present(_ notice: Notice) {
            guard notice != self.notice else { return }
            self.notice = notice
            guard let delay = notice.autoDismiss else { return }
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard self?.notice == notice else { return }
                self?.notice = nil
            }
        }

        func dismissNotice() {
            self.notice = nil
        }
    }
}

// MARK: - Livechat

extension ChatView.ViewModel {

    /// What the header livechat control offers. It shows only while livechat is enabled with its
    /// logo, and always during a session so the visitor can end it.
    enum LivechatControl {
        case hidden, start, end, offline
    }

    var livechatControl: LivechatControl {
        if self.livechatStatus.isInSession { return .end }
        guard self.livechatConfig.enabled, self.livechatConfig.showLivechatLogo else { return .hidden }
        return self.livechatConfig.isAvailable ? .start : .offline
    }

    /// The composer placeholder, naming who the next message goes to.
    var inputPlaceholder: String {
        switch self.livechatStatus {
        case .waiting: L10n.livechatWaitingPlaceholder.string
        case .active: L10n.livechatActivePlaceholder.string
        case .closed: L10n.livechatClosedPlaceholder.string
        case .inactive, .unknown: L10n.inputPlaceholder.string
        }
    }

    /// Takes `/config`'s livechat block and, when livechat is configured, reads whether a session
    /// is already open, so a reopened chat picks up where it left off.
    func startLivechat(with config: LivechatConfig) {
        self.livechatConfig = config
        guard config.configured else { return }
        Task { [livechat = self.livechat] in await livechat.bootstrap() }
    }

    /// Acts on the header control: queues for an agent, ends the session, or says livechat is offline.
    func toggleLivechat() async {
        guard !self.isLivechatBusy else { return }
        switch self.livechatControl {
        case .start: await self.requestLivechat()
        case .end: await self.endLivechat()
        case .offline: self.presentLivechatNotice(L10n.livechatOffline)
        case .hidden: break
        }
    }

    /// Pauses livechat polling while the app is in the background.
    func setSceneActive(_ active: Bool) async {
        await self.livechat.setSceneActive(active)
    }

    /// Pauses livechat polling while the chat is off screen.
    func setVisible(_ visible: Bool) async {
        await self.livechat.setVisible(visible)
    }

    private func requestLivechat() async {
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        let context = LivechatClientContext.native(page: await self.pageContext())
        do {
            try await self.livechat.handover(source: .manualButton, partId: nil, clientContext: context)
        } catch .conflict {
            self.presentLivechatNotice(L10n.livechatOffline)
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed)
        }
    }

    private func endLivechat() async {
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        do {
            try await self.livechat.close(reason: "Switched back to AI chatbot mode")
        } catch .conflict {
            // Nothing is open on the server; read what is.
            await self.livechat.refresh()
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed)
        }
    }

    /// Sends to the agent while a session is active, otherwise to the assistant. A 409 on the
    /// assistant send means a session this device wasn't tracking is active, so the text goes to
    /// the agent instead.
    private func deliver(_ text: String, via provider: any ChatProviding) async throws(ChatProvider.SendFailure) {
        guard self.livechatStatus != .active else {
            try await provider.sendLivechat(text)
            return
        }
        do {
            try await provider.send(text)
        } catch .livechatActive(let popped) {
            await self.livechat.resumeActive()
            try await provider.sendLivechat(popped)
        }
    }

    /// Closes an open session before a reset. A 409 (nothing open) and a refusal that won't change
    /// let the reset go on; a transient failure stops it with a notice so it can be tried again.
    private func closeLivechatBeforeReset() async -> Bool {
        guard self.livechatStatus.isInSession else { return true }
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        do {
            try await self.livechat.close(reason: "Chat reset")
            return true
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
            return false
        } catch {
            guard Self.isTransient(error) else { return true }
            self.presentLivechatNotice(L10n.noticeSendFailed)
            return false
        }
    }

    private static func isTransient(_ error: ChatServiceError) -> Bool {
        switch error {
        case .transport(.http(.unhandled(let status, _))): status >= 500 || status == 408 || status == 429
        case .transport(.connection), .transport(.unknown), .provider: true
        default: false
        }
    }

    /// Mirrors the poller's snapshots: the status, new messages into the conversation, and a
    /// visitor session that ended (401), which clears the conversation like any other 401.
    private func observeLivechat() {
        let stream = self.livechat.stream
        Task { [weak self] in
            for await snapshot in stream {
                await self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: LivechatSnapshot) async {
        self.livechatStatus = snapshot.state.status
        if snapshot.sessionExpired {
            await self.provider?.expireSession()
            self.livechatSessionEnded = true
        } else if !snapshot.messages.isEmpty {
            await self.provider?.appendLivechat(snapshot.messages)
        }
    }

    private func presentLivechatNotice(_ message: LocalizedStringResource) {
        self.present(Notice(edge: .top, message: message.string, autoDismiss: .seconds(4)))
    }
}
