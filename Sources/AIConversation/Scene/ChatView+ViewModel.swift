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
        /// Display name of the connected agent, when the poller last reported one.
        private(set) var livechatAgentName: String?
        /// Whether the connected agent is typing.
        private(set) var isAgentTyping = false
        /// A handover or close is in flight; the header control and reset wait for it.
        private(set) var isLivechatBusy = false
        /// Set when the poller sees the visitor session end (401). The view shows the session-ended
        /// alert and clears it.
        var livechatSessionEnded = false

        /// Shared loader for remote imagery injected into the view environment.
        @ObservationIgnored let imageLoader: ImageLoader
        @ObservationIgnored let conversationFlow: AIChat.ConversationFlow
        /// Host-configured attachment sources; gates the composer attach control and upload prompts.
        @ObservationIgnored let attachments: AIChat.Attachments
        @ObservationIgnored private let encodeAttachment: AttachmentEncoder
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
        /// Bumped by delete, so a handover that was waiting on the host's page context when the
        /// visitor's data went doesn't go ahead.
        @ObservationIgnored private(set) var livechatEpoch = 0
        /// Livechat snapshots older than this generation belong to a visitor a reset or delete
        /// replaced, and are dropped.
        @ObservationIgnored private var livechatFloor: UInt64 = 0

        private(set) var snapshot: ConversationSnapshot?
        /// Drafts of the conversation's forms by `part_id`, created when a snapshot first brings
        /// the form so a draft survives list recycling.
        private(set) var formModels: [String: FormSubmissionModel] = [:]
        var currentMessage = ""
        /// Set when a call the visitor didn't start — a form definition fetch — saw the session
        /// end. The view shows the session-ended alert and resets it.
        var backgroundSessionEnded = false
        /// Composer chips waiting for the next send.
        var pendingAttachments: [PendingAttachment] = []
        /// Picks still being loaded from the library or encoded into chips.
        private var preparingAttachments = 0
        /// True while a pick is being loaded or encoded into a chip.
        var isEncodingAttachment: Bool {
            self.preparingAttachments > 0
        }

        /// Submits a marker-triggered action. Defaults to ``ChatService/submitAction``; tests
        /// inject a stub so form success / failure paths do not need a live network.
        typealias ActionSubmitter = @Sendable (SubmitActionRequest) async throws -> SubmitActionResponse

        /// Fetches a form definition. Defaults to ``ChatService/fetchForm``.
        typealias FormFetcher = @Sendable (String) async throws -> ChatFormDefinition

        /// Encodes picked photo bytes off the main actor. Tests inject a stub.
        typealias AttachmentEncoder = @Sendable (Data, ImageAttachment.Options) throws(ImageAttachment.Failure) -> ImageAttachment.Encoded

        /// Cap on composer chips so a long pick session cannot grow without bound.
        static let maxPendingAttachments = 8

        /// Whether the host offers photo attachments at all.
        var offersAttachments: Bool {
            self.attachments == .photoLibrary
        }

        /// Whether a reply is currently streaming.
        var isStreaming: Bool {
            self.snapshot?.streamingTurnID != nil
        }

        /// The one enable rule for every "add a photo" entry point (composer button, upload-prompt
        /// card): attachments offered, nothing encoding, nothing streaming.
        var canAttach: Bool {
            self.offersAttachments && !self.isEncodingAttachment && !self.isStreaming
        }

        /// Composer attach while livechat is active also requires the server's
        /// ``LivechatConfig/attachmentsEnabled`` flag.
        var canAttachConsideringLivechat: Bool {
            guard self.canAttach else { return false }
            if self.livechatStatus == .active {
                return self.livechatConfig.attachmentsEnabled
            }
            return true
        }

        /// Whether tapping close should present the **conversation** `/rate` overlay.
        var shouldOfferRating: Bool {
            self.conversationRatingMode == .enabled
                && self.onClose != nil
                && !self.conversationRating.hasRated
                && !(self.snapshot?.user.isEmpty ?? true)
                && !self.livechatStatus.isInSession
                && !self.rating.hasPendingFeedback
        }

        /// True when the host provided ``AIChat/Configuration/onClose``.
        var showsCloseButton: Bool {
            self.onClose != nil
        }

        init(
            service: ChatService,
            contextProvider: (@Sendable () async -> String?)?,
            conversationFlow: AIChat.ConversationFlow,
            attachments: AIChat.Attachments,
            onClose: (@MainActor () -> Void)? = nil,
            onLivechatSessionChange: (@MainActor (AIChat.LivechatSessionInfo) -> Void)? = nil,
            conversationRatingMode: AIChat.Rating = .enabled,
            ratingSession: RatingSession = RatingSession(),
            encodeAttachment: AttachmentEncoder? = nil,
            submitAction: ActionSubmitter? = nil,
            fetchForm: FormFetcher? = nil,
            fetchSession: WaitingFormController.SessionFetcher? = nil,
            patchFormValues: WaitingFormController.ValuesPatcher? = nil,
            submitLivechatFeedback: LivechatRatingController.Submitter? = nil,
            rateConversation: ConversationRatingController.Submitter? = nil,
            livechat: LivechatSession? = nil
        ) {
            self.service = service
            self.pageContext = { await contextProvider?() }
            self.conversationFlow = conversationFlow
            self.attachments = attachments
            if let encodeAttachment {
                self.encodeAttachment = encodeAttachment
            } else {
                self.encodeAttachment = { data, options throws(ImageAttachment.Failure) in
                    try ImageAttachment.encode(data, options: options)
                }
            }
            self.onClose = onClose
            self.onLivechatSessionChange = onLivechatSessionChange
            self.conversationRatingMode = conversationRatingMode
            self.submitAction = submitAction ?? { request in
                try await service.submitAction(request)
            }
            let fetchForm = fetchForm ?? { id in
                try await service.fetchForm(id: id)
            }
            self.fetchForm = fetchForm
            self.rating = LivechatRatingController(submitFeedback: submitLivechatFeedback ?? { request in
                try await service.submitLivechatFeedback(request)
            })
            self.conversationRating = ConversationRatingController(
                ratingSession: ratingSession,
                submitRating: rateConversation ?? { request in
                    try await service.rateConversation(request)
                }
            )
            self.livechat = livechat ?? LivechatSession(service: service)
            self.waitingForm = WaitingFormController(
                fetchForm: fetchForm,
                fetchSession: fetchSession ?? { try await service.fetchSession() },
                patchValues: patchFormValues ?? { formId, values in
                    try await service.patchFormValues(formId: formId, values: values)
                }
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

                try? await provider.loadOlder()
                self.waitingForm.configure(formId: config.livechatWaitingFormId)
                self.startLivechat(with: config.livechat)
                self.phase = .ready

            } catch {
                self.phase = .failed
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
                    // A reset or delete is in flight, and its own UI covers the wait.
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
                    self.formModels = [:]
                    self.waitingForm.clear()
                    throw SessionEnded()
                }
            }
        }

        /// Puts a failed send's text and chips back in the composer.
        private func restoreDraft(text: String, attachments: [PendingAttachment]) {
            self.currentMessage = text
            self.pendingAttachments = Self.capped(attachments + self.pendingAttachments)
        }

        /// Encodes a picked photo into a pending attachment chip, dropping the oldest chip once
        /// ``maxPendingAttachments`` is reached.
        func ingestPickedPhoto(_ data: Data) async {
            let livechatDecoded: Int? =
                self.livechatConfig.attachmentsEnabled
                    && (self.livechatStatus == .waiting || self.livechatStatus == .active)
                ? self.livechatConfig.maxAttachmentSizeBytes
                : nil
            let options = ImageAttachment.Options.message(maxDecodedBytes: livechatDecoded)
            guard let pending = await self.encode(data, options: options) else { return }
            self.pendingAttachments = Self.capped(self.pendingAttachments + [pending])
        }

        /// Encodes a pick routed from a `request_image_upload` marker — honours accepted MIME
        /// types (JPEG encode only) and the marker's decoded-byte cap.
        func ingestPromptPhoto(_ data: Data, marker: RequestImageUpload) async {
            guard marker.acceptedTypes.contains("image/jpeg") else {
                self.presentAttachmentFailure()
                return
            }
            let options = ImageAttachment.Options.message(maxDecodedBytes: marker.maxSizeBytes)
            guard let pending = await self.encode(data, options: options) else { return }
            self.pendingAttachments = Self.capped(self.pendingAttachments + [pending])
        }

        /// Encodes a picked photo for a form file field or a ticket attachment.
        func ingestFormPhoto(
            _ data: Data,
            maxBytes: Int,
            filename: String
        ) async -> PendingAttachment? {
            let options = ImageAttachment.Options.action(filename: filename, maxDecodedBytes: maxBytes)
            return await self.encode(data, options: options)
        }

        /// Holds the attach and send controls for as long as `work` runs — from loading the pick
        /// out of the library through its encode — so a send waits for the photo it is meant for.
        func preparingAttachment(_ work: () async -> Void) async {
            self.preparingAttachments += 1
            defer { self.preparingAttachments -= 1 }
            await work()
        }

        /// The one encode path for every composer / prompt / form photo destination.
        private func encode(_ data: Data, options: ImageAttachment.Options) async -> PendingAttachment? {
            self.preparingAttachments += 1
            defer { self.preparingAttachments -= 1 }

            do {
                let encoded = try await Task.detached(priority: .userInitiated) { [encode = self.encodeAttachment] in
                    try encode(data, options)
                }.value
                return PendingAttachment(
                    thumbnail: Image(decorative: encoded.thumbnail, scale: 1),
                    attachment: encoded.attachment,
                    displayName: options.filename ?? L10n.mediaImageLabel.string
                )
            } catch ImageAttachment.Failure.tooLarge {
                self.present(Notice(
                    edge: .bottom,
                    message: L10n.attachmentTooLarge.string,
                    autoDismiss: .seconds(4)
                ))
                return nil
            } catch {
                self.presentAttachmentFailure()
                return nil
            }
        }

        /// Keeps the newest ``maxPendingAttachments`` entries.
        private static func capped(_ attachments: [PendingAttachment]) -> [PendingAttachment] {
            Array(attachments.suffix(Self.maxPendingAttachments))
        }

        /// Surfaces a generic attachment-load failure from the view (picker / transferable miss).
        func presentAttachmentFailure() {
            self.present(Notice(
                edge: .bottom,
                message: L10n.attachmentFailed.string,
                autoDismiss: .seconds(4)
            ))
        }

        /// Clears composer chips when a livechat session that forbids attachments becomes active.
        func dropPendingAttachmentsForLivechat() {
            guard !self.pendingAttachments.isEmpty else { return }
            self.pendingAttachments = []
            self.present(Notice(
                edge: .bottom,
                message: L10n.livechatAttachmentsDropped.string,
                autoDismiss: .seconds(4)
            ))
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

            do {
                let response = try await self.submitAction(request)
                let text = FormSubmissionModel.confirmation(server: response.confirmationText, form: model.form)
                self.formModels[partId]?.markSubmitted(confirmation: text)
                // A contact form can route a livechat handover.
                if self.livechatConfig.configured, !self.livechatStatus.isInSession {
                    Task { [livechat = self.livechat] in await livechat.bootstrap() }
                }
            } catch ChatServiceError.sessionExpired {
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

        /// Loads the next older page of history. A recoverable failure surfaces as a top notice;
        /// a 401 ends the session and escapes as ``SessionEnded`` for the view to alert on.
        func loadOlder() async throws(SessionEnded) {
            if self.notice?.edge == .top { self.dismissNotice() }

            do {
                try await self.provider?.loadOlder()

            } catch ChatServiceError.sessionExpired {
                self.formModels = [:]
                self.waitingForm.clear()
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
        /// close it once the visitor is replaced. A reset during a send does nothing, so the session
        /// is closed only for a reset the provider will accept.
        func reset() async {
            guard !self.isLivechatBusy, !self.isSending, !self.isResetting else { return }
            self.isResetting = true
            defer { self.isResetting = false }
            guard await self.closeLivechatBeforeReset() else { return }
            await self.fenceLivechat()
            do {
                try await self.provider?.reset()
            } catch {
                // A failed reset leaves the conversation, and its form drafts, as they were.
                await self.resumeLivechat()
                return
            }
            self.formModels = [:]
            self.pendingAttachments = []
            self.waitingForm.clear()
            self.conversationRating.clearSession()
        }

        /// Request deletion of visitor data and end the session. Rethrows so the delete sheet can act on the
        /// hook's suspension point — success dismisses it, a failure leaves it open for the host.
        func delete() async throws(DeletionFailed) {
            self.livechatEpoch += 1
            await self.fenceLivechat()
            do {
                try await self.provider?.delete()
            } catch {
                await self.resumeLivechat()
                throw DeletionFailed()
            }
            self.formModels = [:]
            self.pendingAttachments = []
            self.waitingForm.clear()
            self.conversationRating.clearSession()
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
                } catch ChatServiceError.sessionExpired {
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

        /// A 401 outside a send ended the session: the conversation and its form drafts go, as a
        /// send's own 401 clears them, so the next message starts the new session clean.
        private func endSession() async {
            self.formModels = [:]
            self.waitingForm.clear()
            await self.provider?.expireSession()
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

// MARK: - Livechat state

/// The livechat members that write the screen's observable state, beside its storage. Requests,
/// routing and the derived control live in `ChatView+ViewModel+Livechat.swift`.
extension ChatView.ViewModel {

    /// Takes `/config`'s livechat block and, when livechat is configured, reads whether a session
    /// is already open, so a reopened chat picks up where it left off.
    func startLivechat(with config: LivechatConfig) {
        self.livechatConfig = config
        guard config.configured else { return }
        Task { [livechat = self.livechat] in await livechat.bootstrap() }
    }

    /// Acts on the header control: queues for an agent, or ends the session. An offline control
    /// asks too, because availability changes after `/config` is read; a 409 says livechat is offline.
    func toggleLivechat() async {
        guard !self.isLivechatBusy else { return }
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        switch self.livechatControl {
        case .start, .offline: await self.requestLivechat()
        case .end: await self.endLivechat()
        case .hidden: break
        }
    }

    /// Hands over from the `request_human_agent` card in bot turn `turnID`, while
    /// ``canAcceptHumanAgentPrompt(inBotTurn:)`` holds.
    func acceptHumanAgentPrompt(partId: String, inBotTurn turnID: UUID) async {
        guard self.canAcceptHumanAgentPrompt(inBotTurn: turnID) else { return }
        self.isLivechatBusy = true
        defer { self.isLivechatBusy = false }
        await self.requestLivechat(partId: partId)
    }

    /// Ends the chat after a request outside the poller found the visitor session expired (401),
    /// as the poller's own 401 does: the conversation clears, livechat stops, and the view shows
    /// the session-ended alert.
    func endExpiredSession() async {
        self.conversationRating.clearSession()
        await self.provider?.expireSession()
        await self.livechat.teardown()
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
                await self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: LivechatSnapshot) async {
        guard snapshot.generation >= self.livechatFloor else { return }
        let previous = snapshot.previousStatus
        let status = snapshot.state.status
        self.livechatStatus = status
        self.livechatAgentName = snapshot.state.activeAgent?.displayName
        self.isAgentTyping = status == .active && snapshot.state.isAgentTyping
        self.reportLivechatSessionIfChanged()

        if snapshot.sessionExpired {
            self.waitingForm.clear()
            self.conversationRating.clearSession()
            self.rating.update(previous: previous, state: snapshot.state, isRestored: snapshot.isRestored)
            await self.provider?.expireSession()
            self.livechatSessionEnded = true
            return
        }

        self.waitingForm.statusChanged(to: status)

        // Notes mark changes seen live; a restored session changed before this device looked.
        let notesChanges = !snapshot.isRestored
        if notesChanges {
            await self.noteSessionStart(previous: previous, status: status, agentName: self.livechatAgentName)
        }
        if !snapshot.messages.isEmpty {
            await self.provider?.appendLivechat(snapshot.messages)
        }
        if notesChanges, previous.isInSession, status == .closed {
            await self.provider?.note(LivechatNote(kind: .ended))
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
    /// is on screen.
    private func reportLivechatSessionIfChanged() {
        guard self.isChatVisible, self.isSceneActive else { return }
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
