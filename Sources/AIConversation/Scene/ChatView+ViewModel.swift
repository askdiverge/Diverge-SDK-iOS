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
        /// Dismisses the notice on screen. Each notice replaces it, so an older timer can't cut a
        /// newer notice short.
        @ObservationIgnored private var noticeTimer: Task<Void, Never>?

        /// Livechat as `/config` describes it, and the session's status as the poller last saw it.
        private(set) var livechatConfig = LivechatConfig.serverDefaults
        private(set) var livechatStatus = LivechatState.Status.inactive
        /// Display name of the connected agent, when the poller last reported one.
        private(set) var livechatAgentName: String?
        /// Whether the connected agent is typing.
        private(set) var isAgentTyping = false
        /// A handover or close is in flight; the header control and reset wait for it.
        private(set) var isLivechatBusy = false
        /// The visitor asked to leave a session and is deciding whether to.
        var isConfirmingLivechatEnd = false
        /// The status the leave question was asked about. A confirmation counts only while the
        /// session still stands there.
        @ObservationIgnored private var livechatEndQuestion: LivechatState.Status?
        /// Set when the poller sees the visitor session end (401). The view shows the session-ended
        /// alert and clears it.
        var livechatSessionEnded = false

        /// Shared loader for remote imagery injected into the view environment.
        @ObservationIgnored let imageLoader: ImageLoader
        @ObservationIgnored let conversationFlow: AIChat.ConversationFlow
        /// Host-configured attachment sources; gates the composer attach control and upload prompts.
        @ObservationIgnored let attachments: AIChat.Attachments
        @ObservationIgnored let encodeAttachment: AttachmentEncoder
        @ObservationIgnored private let service: ChatService
        @ObservationIgnored let pageContext: @Sendable () async -> String?
        @ObservationIgnored private var provider: (any ChatProviding)?
        @ObservationIgnored private let submitAction: ActionSubmitter
        @ObservationIgnored private let fetchForm: FormFetcher
        @ObservationIgnored let livechat: LivechatSession
        /// The livechat waiting-room form shown above the composer while the visitor is queued.
        @ObservationIgnored let waitingForm: WaitingFormController
        /// Asks the visitor to rate a livechat session that ended while the chat was on screen.
        @ObservationIgnored let rating: LivechatRatingController
        /// Conversation close-rating (`POST /rate`) while the host close button is used.
        @ObservationIgnored let conversationRating: ConversationRatingController
        /// Whether conversation close should present `/rate`.
        @ObservationIgnored private let conversationRatingMode: AIChat.Rating
        /// The host's `onClose` hook, called once the visitor has closed the chat.
        @ObservationIgnored private let onClose: (@MainActor () -> Void)?
        /// The visitor rated or skipped on close, so the host is told once the prompt has gone.
        @ObservationIgnored private var closesAfterRating = false
        /// The host's `onLivechatSessionChange` hook.
        @ObservationIgnored private let onLivechatSessionChange: (@MainActor (AIChat.LivechatSessionInfo) -> Void)?
        /// The last session info delivered to the host, so an unchanged one isn't delivered again.
        @ObservationIgnored private var lastReportedLivechatSession: AIChat.LivechatSessionInfo?
        /// Set once the livechat state has been read, or livechat isn't configured. Until then the
        /// host hears nothing, so a reopened chat doesn't report the default `inactive` over an
        /// open session.
        @ObservationIgnored private var knowsLivechatState = false
        /// Livechat snapshots held while a delete decides whether the visitor goes, so a delete that
        /// fails leaves the session as it was. `nil` while snapshots apply as they arrive.
        @ObservationIgnored private var heldLivechat: [LivechatSnapshot]?
        /// The chat is visible, and the app is active. The host hears about the session, and the
        /// visitor is asked for a rating, only while both hold; see ``screenChanged()``.
        @ObservationIgnored var isChatVisible = true
        @ObservationIgnored var isSceneActive = true
        /// A send is in flight. The provider refuses a reset until it finishes, and a handover waits
        /// for it so the agent's context holds the reply.
        private(set) var isSending = false
        /// A reset is closing the session, replacing the visitor or clearing the conversation; a
        /// send waits for it.
        @ObservationIgnored private var isResetting = false
        /// A history page is on its way. A first page that replaces the conversation holds the
        /// provider, so a reset or delete waits for it.
        private(set) var isLoadingHistory = false
        /// Bumped by delete, so a handover that was waiting on the host's page context when the
        /// visitor's data went doesn't go ahead.
        @ObservationIgnored private(set) var livechatEpoch = 0
        /// Bumped by reset and delete, which replace the visitor, so a form request's 401 that
        /// belongs to the replaced visitor doesn't end the new conversation.
        @ObservationIgnored private var conversationEpoch = 0
        /// Livechat snapshots older than this generation belong to a visitor a reset or delete
        /// replaced, and are dropped.
        @ObservationIgnored private var livechatFloor: UInt64 = 0

        private(set) var snapshot: ConversationSnapshot?
        /// Drafts of the conversation's forms by `part_id`, created when a snapshot first brings
        /// the form so a draft survives list recycling.
        private(set) var formModels: [String: FormSubmissionModel] = [:]
        /// Bot turns whose reply streamed while this chat was open. A form restored from history
        /// stays read-only, the way the web widget does not reopen a form on reload.
        private var liveTurnIDs: Set<UUID> = []
        /// `request_human_agent` cards the visitor answered "No thanks". They leave the
        /// conversation, and the chat stays with the assistant.
        private(set) var declinedHumanAgentPrompts: Set<String> = []
        var currentMessage = ""
        /// Set when a call the visitor didn't start — the first history page or a form definition
        /// fetch — saw the session end. The view shows the session-ended alert and resets it.
        var backgroundSessionEnded = false
        /// Composer chips waiting for the next send.
        var pendingAttachments: [PendingAttachment] = []
        /// Picks still being loaded from the library or encoded into chips.
        var preparingAttachments = 0
        /// Set when a conversation ends while a photo is being prepared, so it can't land in the
        /// next one. Clears once nothing is preparing.
        @ObservationIgnored var discardsPreparedAttachment = false
        /// True while a pick is being loaded or encoded into a chip.
        var isEncodingAttachment: Bool {
            self.preparingAttachments > 0
        }

        /// Submits a marker-triggered action, such as a form. ``Dependencies/live(service:)`` sends
        /// it with ``ChatService/submitAction(_:)``.
        typealias ActionSubmitter = @Sendable (SubmitActionRequest) async throws -> SubmitActionResponse

        /// Fetches a form definition by its id. ``Dependencies/live(service:)`` fetches it with
        /// ``ChatService/fetchForm(id:)``.
        typealias FormFetcher = @Sendable (String) async throws -> ChatFormDefinition

        /// Encodes picked photo bytes off the main actor. Async so a test stub can suspend while
        /// the in-flight state is observed, without blocking a cooperative-pool thread.
        typealias AttachmentEncoder = @Sendable (Data, ImageAttachment.Options) async throws(ImageAttachment.Failure) -> ImageAttachment.Encoded

        /// Whether tapping close should present the **conversation** `/rate` overlay. A livechat
        /// session that closed with a rating of its own (CSAT), given or still to give, is rated
        /// there, so a close after it asks nothing more.
        var shouldOfferRating: Bool {
            self.conversationRatingMode == .enabled
                && self.onClose != nil
                && !self.conversationRating.hasRated
                && !(self.snapshot?.user.isEmpty ?? true)
                && !self.livechatStatus.isInSession
                && !self.rating.closedSessionHasRating
                && !self.isLivechatBusy
        }

        /// True when the host provided ``AIChat/Configuration/onClose``.
        var showsCloseButton: Bool {
            self.onClose != nil
        }

        /// Whether a delete can run now: no send, reset or history page holds the provider, which
        /// would refuse it before the host heard of it.
        var canDeleteData: Bool {
            !self.isSending && !self.isResetting && !self.isLoadingHistory
        }

        init(
            service: ChatService,
            contextProvider: (@Sendable () async -> String?)?,
            conversationFlow: AIChat.ConversationFlow,
            attachments: AIChat.Attachments,
            onClose: (@MainActor () -> Void)?,
            onLivechatSessionChange: (@MainActor (AIChat.LivechatSessionInfo) -> Void)?,
            conversationRatingMode: AIChat.Rating,
            ratingSession: RatingSession,
            dependencies: Dependencies
        ) {
            self.service = service
            self.pageContext = { await contextProvider?() }
            self.conversationFlow = conversationFlow
            self.attachments = attachments
            self.encodeAttachment = dependencies.encodeAttachment
            self.onClose = onClose
            self.onLivechatSessionChange = onLivechatSessionChange
            self.conversationRatingMode = conversationRatingMode
            self.submitAction = dependencies.submitAction
            self.fetchForm = dependencies.fetchForm
            self.rating = LivechatRatingController(submitFeedback: dependencies.submitLivechatFeedback)
            self.conversationRating = ConversationRatingController(
                ratingSession: ratingSession,
                submitRating: dependencies.rateConversation
            )
            self.livechat = dependencies.livechat
            self.waitingForm = WaitingFormController(
                fetchForm: dependencies.fetchForm,
                fetchSession: dependencies.fetchSession,
                patchValues: dependencies.patchFormValues
            )
            // Product/table imagery fills ~half-width, ~800px covers 3x.
            self.imageLoader = ImageLoader(maxPixelSize: 800) { try await service.fetchData($0) }
            self.observeLivechat()
            self.waitingForm.bind(onSessionExpired: { [weak self] in await self?.endExpiredSession() })
            self.rating.bind(
                onSessionExpired: { [weak self] in await self?.endExpiredSession() },
                refresh: { [weak self] in await self?.livechat.refresh() }
            )
            self.conversationRating.bind(onSessionExpired: { [weak self] in await self?.endExpiredSession() })
        }

        /// The visitor tapped close: the conversation rating opens when one is due, and otherwise
        /// the host's `onClose` is called.
        func close() {
            if self.shouldOfferRating {
                self.conversationRating.begin()
            } else {
                self.onClose?()
            }
        }

        /// The visitor skipped the rating: nothing is sent, and the host hears the close once the
        /// prompt has gone.
        func skipRating() {
            self.closesAfterRating = true
            self.conversationRating.dismiss()
        }

        /// Sends the rating. Once it is stored the host hears the close, after the prompt has
        /// gone; a refused rating stays on the prompt.
        func submitRating(score: Int, feedback: String?) async {
            if await self.conversationRating.submit(score: score, feedback: feedback) {
                self.closesAfterRating = true
            }
        }

        /// The rating prompt finished going away; a close the visitor asked for goes to the host.
        func ratingDidDismiss() {
            guard self.closesAfterRating else { return }
            self.closesAfterRating = false
            self.onClose?()
        }

        /// A livechat loop parked while the chat is off screen holds its session; this ends it.
        deinit {
            self.livechat.stop()
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
                    welcomeMessage: config.display.welcomeMessage,
                    acceptsImageUploadPrompts: self.attachments == .photoLibrary
                )

                self.provider = provider
                self.observe(provider)

                // The chat opens even when history doesn't: a failed page shows its notice and can
                // be asked for again. A 401 means the session has ended, and the visitor hears it
                // now rather than when their first message is refused.
                do {
                    try await self.loadOlder()
                } catch {
                    self.backgroundSessionEnded = true
                }
                // The view went away mid-start and cancelled what was still loading, the history
                // or an image among it; its next appearance starts again.
                guard !Task.isCancelled else {
                    self.provider = nil
                    self.phase = .loading
                    return
                }
                self.waitingForm.configure(formId: config.livechatWaitingFormId)
                self.startLivechat(with: config.livechat)
                self.phase = .ready

            } catch {
                self.phase = Task.isCancelled ? .loading : .failed
            }
        }

        /// Sends a user message (draft text and any pending attachments), to the agent while a
        /// livechat session is active and otherwise to the assistant. Recoverable failures
        /// (busy, retryable) bounce inline as a notice so the input stays stateless; a 401 ends
        /// the session and escapes as ``SessionEnded`` for the view to alert on.
        func send() async throws(SessionEnded) {
            if self.notice?.edge == .bottom { self.dismissNotice() }
            let text = self.currentMessage
            let attachments = self.pendingAttachments
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            guard let provider = self.provider, hasText || !attachments.isEmpty else { return }
            guard !self.isSending, !self.isResetting else {
                self.present(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))
                return
            }
            // An agent session that refuses photos gets none; the text stays for the next send.
            if !attachments.isEmpty, self.livechatStatus == .active, !self.livechatConfig.attachmentsEnabled {
                self.dropPendingAttachmentsForLivechat()
                return
            }
            self.isSending = true
            defer { self.isSending = false }

            self.currentMessage = ""
            self.pendingAttachments = []

            do {
                await self.livechat.endTyping()
                try await self.deliver(
                    hasText ? text : "",
                    attachments: attachments.map(\.attachment),
                    via: provider
                )

            } catch {
                switch error {
                case .busy(.streaming):
                    self.restoreDraft(text: text, attachments: attachments)
                    self.present(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))

                case .busy(.operation):
                    // A reset, a delete or a first history page that replaces the conversation is
                    // in flight, and its own UI covers the wait.
                    self.restoreDraft(text: text, attachments: attachments)

                case .retry(popped: let draft, body: let body):
                    self.restoreDraft(text: draft.text, attachments: attachments)
                    self.present(Notice(edge: .bottom, message: body ?? L10n.noticeSendFailed.string, autoDismiss: nil))

                case .livechatInactive(popped: let draft):
                    // The agent session ended; the restored draft goes to the assistant next time.
                    self.restoreDraft(text: draft.text, attachments: attachments)
                    self.present(Notice(edge: .bottom, message: L10n.noticeLivechatEnded.string, autoDismiss: nil))
                    await self.livechat.refresh()

                case .livechatActive(popped: let draft):
                    self.restoreDraft(text: draft.text, attachments: attachments)
                    self.present(Notice(edge: .bottom, message: L10n.noticeSendFailed.string, autoDismiss: nil))

                case .sessionExpired:
                    await self.fenceLivechat()
                    self.dropConversationState()
                    // The conversation is gone, but what the visitor just wrote can still be sent.
                    self.restoreDraft(text: text, attachments: attachments)
                    throw SessionEnded()
                }
            }
        }

        /// Whether a form card in the given bot turn may still be filled: the turn is the newest
        /// bot turn (the server rejects older `part_id`s) and its reply streamed while the chat
        /// was open.
        func isFormEditable(inBotTurn turnID: UUID) -> Bool {
            self.snapshot?.lastBotTurnID == turnID && self.liveTurnIDs.contains(turnID)
        }

        /// Sets a text or dropdown answer on the draft of form `partId`.
        func setFormValue(_ value: String, for key: String, inForm partId: String) {
            self.formModels[partId]?.setValue(value, for: key)
        }

        /// Attaches or clears a picked photo on a custom-form file field.
        func setFormFile(_ file: PendingAttachment?, for key: String, inForm partId: String) {
            self.formModels[partId]?.setFile(file, for: key)
        }

        /// Attaches or clears the support-ticket photo.
        func setTicketAttachment(_ file: PendingAttachment?, inForm partId: String) {
            self.formModels[partId]?.setTicketAttachment(file)
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
        /// validation, forms already submitting or submitted, and a form whose reply still streams.
        func submitForm(partId: String) async throws(SessionEnded) {
            guard let model = self.formModels[partId], !model.isSubmitting, !model.isSubmitted,
                  !self.isStreaming(formIn: partId)
            else { return }
            guard self.formModels[partId]?.validate(offersFileFields: self.offersAttachments) == true else { return }
            guard let request = model.buildRequest() else {
                self.formModels[partId]?.markFailed()
                return
            }
            guard self.formModels[partId]?.beginSubmitting() == true else { return }
            let epoch = self.conversationEpoch

            do {
                let response = try await self.submitAction(request)
                let text = FormSubmissionModel.confirmation(server: response.confirmationText, form: model.form)
                self.formModels[partId]?.markSubmitted(confirmation: text)
                // A contact form can route a livechat handover.
                if self.livechatConfig.configured, !self.livechatStatus.isInSession {
                    Task { [livechat = self.livechat] in await livechat.bootstrap() }
                }
            } catch ChatServiceError.sessionExpired {
                // A form sent before a reset or delete belonged to the visitor it replaced.
                guard epoch == self.conversationEpoch else { return }
                await self.endSession()
                throw SessionEnded()
            } catch ChatServiceError.conflict {
                self.formModels[partId]?.markAlreadySubmitted()
            } catch ChatServiceError.validation(_, let params) {
                self.formModels[partId]?.applyServerErrors(params: params)
            } catch {
                self.formModels[partId]?.markFailed()
            }
        }

        /// Loads the next older page of history, returning whether it loaded. A recoverable
        /// failure surfaces as a top notice; a 401 ends the session and escapes as
        /// ``SessionEnded`` for the view to alert on.
        @discardableResult
        func loadOlder() async throws(SessionEnded) -> Bool {
            if self.notice?.edge == .top { self.dismissNotice() }
            self.isLoadingHistory = true
            defer { self.isLoadingHistory = false }

            do {
                try await self.provider?.loadOlder()
                return true

            } catch ChatServiceError.sessionExpired {
                await self.fenceLivechat()
                self.dropConversationState()
                throw SessionEnded()

            } catch {
                // A page whose caller went away, such as a start the view cancelled, didn't fail.
                guard !Task.isCancelled else { return false }
                self.present(Notice(
                    edge: .top,
                    message: L10n.noticeHistoryLoadFailed.string,
                    autoDismiss: .seconds(4)
                ))
                return false
            }
        }

        /// Resets the conversation. An open livechat session is closed first, because nobody could
        /// close it once the visitor is replaced; the view asks the visitor to confirm that. A reset
        /// during a send or a history load does nothing, and a rotation that fails after a close
        /// leaves the conversation in place with a notice.
        func reset() async {
            guard !self.isLivechatBusy, !self.isSending, !self.isResetting, !self.isLoadingHistory else { return }
            self.isResetting = true
            defer { self.isResetting = false }
            let closesSession = self.livechatStatus.isInSession
            guard await self.closeLivechatBeforeReset() else { return }
            await self.fenceLivechat()
            self.conversationEpoch += 1
            do {
                try await self.provider?.reset()
            } catch {
                // A failed reset leaves the conversation, and its form drafts, as they were. The
                // session it closed stays closed, so the visitor hears the reset didn't happen.
                await self.resumeLivechat()
                if closesSession {
                    self.presentLivechatNotice(L10n.noticeSendFailed)
                }
                return
            }
            self.dropConversationState()
            self.dropComposerPhotos()
        }

        /// Request deletion of visitor data and end the session. Rethrows so the delete sheet can act on the
        /// hook's suspension point — success dismisses it, a failure leaves it open for the host. A
        /// send or reset in flight would refuse it before the host heard of it, so the sheet's confirm
        /// waits for them. Livechat snapshots are held until the delete settles, so a delete that
        /// fails leaves the session as it was.
        func delete() async throws(DeletionFailed) {
            guard self.canDeleteData else { throw DeletionFailed() }
            self.livechatEpoch += 1
            self.conversationEpoch += 1
            self.heldLivechat = []
            do {
                try await self.provider?.delete()
            } catch {
                await self.releaseHeldLivechat()
                throw DeletionFailed()
            }
            await self.fenceLivechat()
            await self.releaseHeldLivechat()
            self.dropConversationState()
            self.dropComposerPhotos()
        }

        /// Test seam — attach a stub provider without bootstrapping `/config`.
        func attachProviderForTesting(_ provider: some ChatProviding) {
            self.provider = provider
            self.observe(provider)
        }

        /// Pre-loads a config image once, downsampled, so it isn't re-fetched during rendering.
        private func loadImage(_ url: URL?, maxPixelSize: CGFloat) async -> Image? {
            // A logo or avatar that won't load leaves the chat without it.
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
                    if let streaming = snapshot.streamingTurnID, self?.liveTurnIDs.contains(streaming) == false {
                        self?.liveTurnIDs.insert(streaming)
                    }
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
            let epoch = self.conversationEpoch
            Task { [weak self, fetchForm = self.fetchForm] in
                do {
                    let definition = try await fetchForm(formId)
                    self?.formModels[partId]?.applyHydratedDefinition(definition)
                } catch ChatServiceError.sessionExpired {
                    // A fetch started before a reset or delete belonged to the visitor it replaced.
                    guard epoch == self?.conversationEpoch else { return }
                    await self?.endSession()
                    self?.backgroundSessionEnded = true
                } catch ChatServiceError.notFound {
                    self?.formModels[partId]?.markUnavailable()
                } catch {
                    self?.formModels[partId]?.failHydrating()
                }
            }
        }

        /// Whether the reply that brought form `partId` is still streaming. The backend saves the
        /// form when that stream ends, so a submit before then is rejected.
        private func isStreaming(formIn partId: String) -> Bool {
            guard let snapshot = self.snapshot, let streaming = snapshot.streamingTurnID else { return false }
            return snapshot.incoming.contains { turn in
                turn.id == streaming && turn.model.contains { response in
                    if case .form(let form) = response { form.partId == partId } else { false }
                }
            }
        }

        /// A 401 outside a send ended the session: livechat stops, and the conversation and its form
        /// drafts go, as a send's own 401 clears them, so the next message starts the new session
        /// clean.
        private func endSession() async {
            await self.fenceLivechat()
            self.dropConversationState()
            await self.provider?.expireSession()
        }

        /// Drops what belonged to the conversation that just ended, however it ended: its form
        /// drafts, the waiting card and whether it was rated. The composer keeps its draft, text
        /// and photos, so a message the visitor hasn't sent can still go to the next session.
        private func dropConversationState() {
            self.formModels = [:]
            self.liveTurnIDs = []
            self.declinedHumanAgentPrompts = []
            self.waitingForm.clear()
            self.conversationRating.clearSession()
        }

        /// Drops the photos in the composer and any still being prepared, when the visitor resets
        /// the conversation or deletes their data.
        private func dropComposerPhotos() {
            self.pendingAttachments = []
            self.discardsPreparedAttachment = self.isEncodingAttachment
        }

        func present(_ notice: Notice) {
            guard notice != self.notice else { return }
            self.notice = notice
            self.noticeTimer?.cancel()
            guard let delay = notice.autoDismiss else { return }
            self.noticeTimer = Task { [weak self] in
                // Only cancellation throws here, and the guard below handles that.
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.notice = nil
            }
        }

        func dismissNotice() {
            self.noticeTimer?.cancel()
            self.notice = nil
        }
    }
}

// MARK: - Livechat state

/// The livechat members that write the screen's observable state, beside its storage. Requests,
/// routing and the derived control live in `ChatView+ViewModel+Livechat.swift`.
extension ChatView.ViewModel {

    /// Takes `/config`'s livechat block and, when livechat is configured, reads whether a session
    /// is already open, so a reopened chat picks up where it left off.
    func startLivechat(with config: LivechatConfig) {
        self.livechatConfig = config
        guard config.configured else {
            // No session can open, so `inactive` is the state.
            self.knowsLivechatState = true
            self.reportLivechatSessionIfChanged()
            return
        }
        Task { [livechat = self.livechat] in await livechat.bootstrap() }
    }

    /// Acts on the header control: queues for an agent, or asks the visitor to confirm leaving the
    /// session. An offline control asks too, because availability changes after `/config` is read;
    /// a 409 says livechat is offline.
    func toggleLivechat() async {
        guard !self.isLivechatBusy else { return }
        switch self.livechatControl {
        case .start, .offline:
            self.isLivechatBusy = true
            defer { self.isLivechatBusy = false }
            await self.requestLivechat()
        case .end:
            self.livechatEndQuestion = self.livechatStatus
            self.isConfirmingLivechatEnd = true
        case .hidden:
            break
        }
    }

    /// The visitor confirmed leaving. The answer counts only for the session the question asked
    /// about: one that ended meanwhile stays ended, so a late answer can't queue the visitor again,
    /// and an agent who joined the queue meanwhile keeps their chat.
    func confirmEndLivechat() async {
        self.isConfirmingLivechatEnd = false
        let asked = self.livechatEndQuestion
        self.livechatEndQuestion = nil
        guard !self.isLivechatBusy, self.livechatControl == .end, asked == self.livechatStatus else { return }
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        await self.endLivechat()
    }

    /// Hands over from the `request_human_agent` card in bot turn `turnID`, while
    /// ``canAcceptHumanAgentPrompt(inBotTurn:)`` holds.
    func acceptHumanAgentPrompt(partId: String, inBotTurn turnID: UUID) async {
        guard self.canAcceptHumanAgentPrompt(inBotTurn: turnID) else { return }
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        await self.requestLivechat(partId: partId)
    }

    /// Answers "No thanks" to the `request_human_agent` card `partId`: the card leaves the
    /// conversation, no handover is requested, and the chat stays with the assistant.
    func declineHumanAgentPrompt(partId: String) {
        self.declinedHumanAgentPrompts.insert(partId)
    }

    /// Ends the chat after a request outside the poller found the visitor session expired (401),
    /// as the poller's own 401 does: the conversation clears, livechat stops, and the view shows
    /// the session-ended alert.
    func endExpiredSession() async {
        await self.fenceLivechat()
        self.dropConversationState()
        await self.provider?.expireSession()
        self.livechatSessionEnded = true
    }

    func presentLivechatNotice(_ message: LocalizedStringResource) {
        self.present(Notice(edge: .top, message: message.string, autoDismiss: .seconds(4)))
    }

    /// Closes an open session before a reset. A 409 (nothing open) and a refusal that won't change
    /// let the reset go on; a transient failure stops it with a notice so it can be tried again.
    private func closeLivechatBeforeReset() async -> Bool {
        guard self.livechatStatus.isInSession else { return true }
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        do {
            try await self.livechat.close(reason: LivechatCloseRequest.resetReason)
            return true
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
            return false
        } catch {
            guard error.isTransient else { return true }
            self.presentLivechatNotice(L10n.noticeSendFailed)
            return false
        }
    }

    /// Mirrors the poller's snapshots: the status, new messages into the conversation, and a
    /// visitor session that ended (401), which clears the conversation like any other 401.
    private func observeLivechat() {
        let stream = self.livechat.stream
        Task { [weak self] in
            for await snapshot in stream {
                await self?.receive(snapshot)
            }
        }
    }

    /// Applies a snapshot, or holds it while a delete decides whether the visitor goes.
    private func receive(_ snapshot: LivechatSnapshot) async {
        guard self.heldLivechat == nil else {
            self.heldLivechat?.append(snapshot)
            return
        }
        await self.apply(snapshot)
    }

    /// Applies the snapshots held during a delete, in order, then lets new ones through.
    private func releaseHeldLivechat() async {
        while let next = self.heldLivechat?.first {
            self.heldLivechat?.removeFirst()
            await self.apply(next)
        }
        self.heldLivechat = nil
    }

    private func apply(_ snapshot: LivechatSnapshot) async {
        guard snapshot.generation >= self.livechatFloor else { return }
        self.knowsLivechatState = true
        let previous = snapshot.previousStatus
        let status = snapshot.state.status
        // The leave question was asked about the session as it stood, so a change of status takes
        // it down: an agent joining turns leaving the queue into ending their chat.
        if status != self.livechatStatus {
            self.isConfirmingLivechatEnd = false
        }
        self.livechatStatus = status
        self.livechatAgentName = snapshot.state.activeAgent?.displayName
        self.isAgentTyping = status == .active && snapshot.state.isAgentTyping
        self.reportLivechatSessionIfChanged()

        if snapshot.sessionExpired {
            self.dropConversationState()
            self.rating.update(previous: previous, state: snapshot.state, isRestored: snapshot.isRestored)
            await self.provider?.expireSession()
            self.livechatSessionEnded = true
            return
        }

        self.waitingForm.statusChanged(to: status)
        // An agent is taking over, so a close prompt still up no longer applies.
        if status.isInSession {
            self.conversationRating.dismiss()
        }

        // Notes are kept in memory, so a restored session says where it stands. How it got there
        // happened before this device looked, which is why its end goes unnoted.
        await self.noteSessionStart(
            previous: snapshot.isRestored ? .inactive : previous,
            status: status,
            agentName: self.livechatAgentName
        )
        if !snapshot.messages.isEmpty {
            await self.provider?.appendLivechat(snapshot.messages)
        }
        if !snapshot.isRestored, previous.isInSession, status == .closed {
            let kind: LivechatNote.Kind = snapshot.state.isClosedForInactivity ? .endedForInactivity : .ended
            await self.provider?.note(LivechatNote(kind: kind))
        }
        self.rating.update(previous: previous, state: snapshot.state, isRestored: snapshot.isRestored)
    }

    /// Follows the chat going on or off screen: the rating prompt waits for it, and the host hears
    /// the session's latest state when it comes back.
    func screenChanged() {
        let onScreen = self.isChatVisible && self.isSceneActive
        self.rating.setOnScreen(onScreen)
        self.reportLivechatSessionIfChanged()
    }

    /// Delivers the session to the host's `onLivechatSessionChange` when it changed, while the chat
    /// is on screen and once its state is known.
    private func reportLivechatSessionIfChanged() {
        guard self.knowsLivechatState, self.isChatVisible, self.isSceneActive else { return }
        let info = AIChat.LivechatSessionInfo(self.livechatStatus, agentName: self.livechatAgentName)
        guard info != self.lastReportedLivechatSession else { return }
        self.lastReportedLivechatSession = info
        self.onLivechatSessionChange?(info)
    }

    /// Notes the visitor joining the queue and an agent joining, ahead of the messages that follow.
    private func noteSessionStart(
        previous: LivechatState.Status,
        status: LivechatState.Status,
        agentName: String?
    ) async {
        if previous != .waiting, status == .waiting {
            await self.provider?.note(LivechatNote(kind: .queued))
        }
        if previous != .active, status == .active {
            let name = (agentName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? L10n.livechatAgentFallback.string
            await self.provider?.note(LivechatNote(kind: .agentJoined(displayName: name)))
            if !self.livechatConfig.attachmentsEnabled {
                self.dropPendingAttachmentsForLivechat()
            }
        }
    }

    /// Stops livechat before a reset or delete replaces the visitor, and drops the snapshots of
    /// the old session still on their way, so its messages can't land in the new conversation.
    private func fenceLivechat() async {
        self.livechatFloor = await self.livechat.teardown()
    }

    /// Reads the session again after a failed reset or delete left the visitor in place.
    private func resumeLivechat() async {
        guard self.livechatConfig.configured else { return }
        await self.livechat.bootstrap()
    }
}
