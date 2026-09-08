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

        /// Builds the session data layer. Defaults to ``ChatProvider``; tests inject a stub.
        /// Arguments: service, page context, welcome message, whether upload prompts render,
        /// whether human-agent prompts render.
        typealias ProviderFactory = (
            any ChatServicing,
            @escaping @Sendable () async -> String?,
            String?,
            Bool,
            Bool
        ) -> any ChatProviding

        /// Turns picked photo bytes into a wire attachment for the given destination. Defaults to
        /// ``ImageAttachment/encode(_:options:)``; tests inject a stub to drive the failure paths
        /// on both the composer and the form routes.
        typealias AttachmentEncoder = @Sendable (
            Data,
            ImageAttachment.Options
        ) throws(ImageAttachment.Failure) -> ImageAttachment.Encoded

        /// Submits a marker-triggered action. Defaults to ``ChatService/submitAction``; tests
        /// inject a stub so form success / failure paths do not need a live network.
        typealias ActionSubmitter = @Sendable (SubmitActionRequest) async throws -> SubmitActionResponse

        /// Submits a conversation rating. Defaults to ``ChatService/rateConversation``; tests inject
        /// a stub. Untyped throws — typed throws crash the 6.x frontend when captured as `@Sendable`.
        typealias RatingSubmitter = @Sendable (RateConversationRequest) async throws -> Void

        /// Submits livechat CSAT. Defaults to ``ChatService/submitLivechatFeedback``; tests inject a stub.
        typealias LivechatFeedbackSubmitter = @Sendable (RateConversationRequest) async throws -> LivechatFeedbackResponse

        /// Fetches a form definition. Defaults to ``ChatService/fetchForm``; tests inject a stub.
        typealias FormFetcher = @Sendable (String) async throws -> ChatFormDefinition

        /// Fetches session values. Defaults to ``ChatService/fetchSession``; tests inject a stub.
        typealias SessionFetcher = @Sendable () async throws -> ChatSessionState

        /// Patches form session values. Defaults to ``ChatService/patchFormValues``; tests inject a stub.
        typealias FormValuesPatcher = @Sendable (String, [String: String]) async throws -> ChatSessionState

        /// How many photos may ride along with one message. The strip, bounce restore, and wire
        /// path already handle N; 8 is the UX cap so a long chip row stays usable.
        static let maxPendingAttachments = 8

        private(set) var phase: Phase = .loading
        private(set) var appearance: ChatAppearance?

        private(set) var name = ""
        private(set) var subtitle: Subtitle?
        private(set) var privacyPolicyURL: URL?
        private(set) var avatar: Image?
        private(set) var logo: HeaderLogo?
        private(set) var notice: Notice?
        /// Filtered starter chips for the current page context (empty when none / already chatting).
        private(set) var startPrompts: [StartPrompt] = []
        /// Active in-chat promo banners from `GET /api/v1/chat/banners` (empty when none / soft-fail).
        private(set) var banners: [ChatBanner] = []
        /// In-memory dismiss keys (content fingerprints) for this ``AIChat`` session.
        private var dismissedBannerFingerprints: Set<String> = []
        /// Waiting-room form id from `/config.forms` (`livechat_waiting`), if any.
        /// Internal so ``ChatView+WaitingForm`` can write it (`private` is file-scoped).
        var waitingFormId: String?
        /// Draft for the waiting-room form card (nil when not waiting / not configured / soft-fail).
        var waitingFormModel: WaitingFormModel?
        /// Guards concurrent loads when the poller ticks waiting repeatedly.
        var waitingFormLoadInFlight = false
        /// Set when a session-bound call (banners 401 / waiting-form 401) expires the visitor token.
        /// ``ChatView`` presents the same session-ended alert as send / export.
        var sessionEnded = false
        /// Dashboard open-product CTA label; `nil` → localised ``L10n/productOpen`` at the view.
        private(set) var productOpenLabel: String?
        /// Whether `/config` enabled add-to-cart **and** the host supplied ``onAddToCart``.
        /// Per-card sku is applied in ``ProductGridView/shouldOfferCart(for:onAddToCart:)``.
        private(set) var showsAddToCart = false

        // Livechat — mirrored from config + the ``LivechatSession`` poller.
        let livechat = LivechatMirror()
        @ObservationIgnored var livechatSession: LivechatSession?
        @ObservationIgnored var typingIdleTask: Task<Void, Never>?
        @ObservationIgnored var livechatObserveStarted = false
        @ObservationIgnored var isTypingSent = false
        /// Test seam — skip livechat HTTP so typing / handover unit tests stay off-network.
        @ObservationIgnored var suppressLivechatNetwork = false
        /// Test seam — visitor typing posts (`true` once per burst, then `false` on idle/send).
        var typingPosts: [Bool] = []

        /// Config+hook gate for the grid; `nil` when cart is off so the view takes one optional.
        var productAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)? {
            self.showsAddToCart ? self.onAddToCart : nil
        }

        /// Shared loader for remote imagery injected into the view environment.
        @ObservationIgnored let imageLoader: ImageLoader
        @ObservationIgnored let conversationFlow: AIChat.ConversationFlow
        /// Which attachment sources the composer offers — host-configured, see ``AIChat/Attachments``.
        @ObservationIgnored let attachments: AIChat.Attachments
        /// From `/config` `image_enabled`. Omitted APIs leave this `true` so the host gate is the
        /// only switch. Host ``AIChat/Attachments/disabled`` still wins.
        private var chatbotImageEnabled = true
        /// Whether to offer the rating overlay on close — host-configured, see ``AIChat/Rating``.
        @ObservationIgnored let rating: AIChat.Rating
        /// Palette selection — host-configured, see ``AIChat/Appearance``.
        @ObservationIgnored let appearancePreference: AIChat.Appearance
        /// Host dismiss hook. Non-`nil` enables the SDK close button.
        @ObservationIgnored let onClose: (() -> Void)?
        /// Host cart hook. Combined with config `product_card.add_to_cart.enabled` for the cart button.
        @ObservationIgnored let onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)?
        /// Host livechat session hook — status / agent-name changes only.
        @ObservationIgnored let onLivechatSessionChange: (@MainActor (AIChat.LivechatSessionInfo) -> Void)?
        /// Last payload delivered to ``onLivechatSessionChange`` (dedupe).
        @ObservationIgnored var lastReportedLivechatSession: AIChat.LivechatSessionInfo?
        @ObservationIgnored let service: ChatService
        /// Per-message / handover page string — internal so ``ChatView+Livechat`` can read it.
        @ObservationIgnored let pageContext: @Sendable () async -> String?
        @ObservationIgnored private let makeProvider: ProviderFactory
        @ObservationIgnored private let encodeAttachment: AttachmentEncoder
        @ObservationIgnored private let submitAction: ActionSubmitter
        @ObservationIgnored private let rateConversation: RatingSubmitter
        @ObservationIgnored private let submitLivechatFeedbackRequest: LivechatFeedbackSubmitter
        /// Waiting-form network seams — internal so ``ChatView+WaitingForm`` can call them.
        @ObservationIgnored let fetchForm: FormFetcher
        @ObservationIgnored let fetchSession: SessionFetcher
        @ObservationIgnored let patchFormValues: FormValuesPatcher
        @ObservationIgnored private let submittedForms: SubmittedFormStore
        @ObservationIgnored private let ratingSession: RatingSession
        @ObservationIgnored var provider: (any ChatProviding)?
        /// Per-form draft state, keyed by `partId` so list recycling keeps answers.
        @ObservationIgnored private var formModels: [String: FormSubmissionModel] = [:]
        /// Draft for the currently presented rating overlay (rebuilt each presentation).
        @ObservationIgnored private(set) var ratingModel: RatingSubmissionModel?

        private(set) var snapshot: ConversationSnapshot?
        var currentMessage = ""
        /// Photos waiting to ride along with the next send (at most ``maxPendingAttachments``).
        /// Restored on a recoverable bounce.
        var pendingAttachments: [PendingAttachment] = []
        /// True while a picked photo is being downsampled / encoded.
        private(set) var isEncodingAttachment = false

        /// True while an assistant reply is streaming.
        var isStreaming: Bool {
            self.snapshot?.streamingTurnID != nil
        }

        /// Whether the host **and** this chatbot allow photo attach. Host ``AIChat/Attachments/disabled``
        /// always wins; `/config` `image_enabled: false` hides attach even when the host opted in.
        var offersAttachments: Bool {
            self.attachments == .photoLibrary && self.chatbotImageEnabled
        }

        /// The one enable rule for every "add a photo" entry point (composer button, upload-prompt
        /// card): attachments offered, nothing encoding, nothing streaming.
        var canAttach: Bool {
            self.offersAttachments && !self.isEncodingAttachment && !self.isStreaming
        }

        /// Whether a form card in the given bot turn may still be filled — only the newest bot
        /// turn's forms are actionable (the server rejects older `part_id`s).
        func isFormEditable(inBotTurn turnID: UUID) -> Bool {
            self.snapshot?.lastBotTurnID == turnID
        }

        /// Whether tapping close should present the **conversation** `/rate` overlay.
        /// Requires the host to have enabled ``AIChat/Configuration/rating``, a conversation with
        /// at least one user turn, and that this session has not already rated.
        /// Suppressed while livechat is waiting/active or after a closed livechat (CSAT owns
        /// that close). Livechat CSAT ignores ``AIChat/Configuration/rating``.
        var shouldOfferRating: Bool {
            self.rating == .enabled
                && self.onClose != nil
                && !self.ratingSession.hasRated
                && self.snapshot?.lastUserTurnID != nil
                && !self.livechat.isInSession
                && self.livechat.status != .closed
        }

        /// Closed + `feedback.pending` and not dismissed — present CSAT (bootstrap, closed edge,
        /// or Chat Close last chance). Not gated by ``AIChat/Configuration/rating``.
        var canOfferLivechatCSAT: Bool {
            self.livechat.status == .closed
                && self.livechat.feedback.status == .pending
                && !self.dismissedLivechatFeedback
        }

        /// Overlay pending or already on screen for this closed session — block a new handover.
        var isLivechatCSATBlockingHandover: Bool {
            self.livechat.status == .closed
                && (self.livechatCSATPending || self.ratingModel != nil)
                && !self.dismissedLivechatFeedback
        }

        /// What Chat Close should do. The view calls `onClose` only on ``CloseDecision/handoffToHost``.
        enum CloseDecision: Equatable {
            /// Skip a visible livechat CSAT overlay (no POST) or nothing to ask — then `onClose`.
            case handoffToHost
            /// Present livechat CSAT (closed + pending, overlay not showing).
            case presentLivechatCSAT
            /// Present conversation `/rate`.
            case presentConversationRating
        }

        /// Set when `feedback.status == pending` and the visitor has not dismissed.
        /// `ChatView` presents the CSAT overlay then clears it.
        private(set) var livechatCSATPending = false
        /// Local skip/dismiss for this closed session — cleared when a new waiting/active session starts.
        private var dismissedLivechatFeedback = false

        /// True when the host provided ``AIChat/Configuration/onClose`` — the close button only
        /// renders then, so integrators who do not adopt the hook see today's behaviour.
        var showsCloseButton: Bool {
            self.onClose != nil
        }

        /// Resolves the active color scheme from the host preference and the environment.
        func resolvedScheme(environment: ColorScheme) -> ColorScheme {
            switch self.appearancePreference {
            case .system: environment
            case .light: .light
            case .dark: .dark
            }
        }

        /// System chrome follows the **painted** palette, not the host lock alone.
        /// `nil` while `appearance` is unset (loading / failed) so the environment owns chrome.
        /// A cloned `dark_theme` paints light, so a `.dark` lock still returns `.light`.
        func preferredColorScheme(for appearance: ChatAppearance?) -> ColorScheme? {
            appearance?.chromeColorScheme
        }

        /// Whether this ``AIChat`` instance has already submitted a rating.
        var ratingSessionHasRated: Bool {
            self.ratingSession.hasRated
        }

        /// Whether the start-prompt chips should render below the conversation — configured
        /// prompts exist, the visitor has not sent a user turn yet, and nothing is streaming.
        var shouldShowStartPrompts: Bool {
            !self.startPrompts.isEmpty
                && self.snapshot?.lastUserTurnID == nil
                && !self.isStreaming
        }

        /// Banners still visible after in-memory dismiss. Blank-message rows are dropped.
        var visibleBanners: [ChatBanner] {
            self.banners.filter {
                $0.hasVisibleMessage
                    && !self.dismissedBannerFingerprints.contains($0.contentFingerprint)
            }
        }

        init(
            service: ChatService,
            contextProvider: (@Sendable () async -> String?)?,
            conversationFlow: AIChat.ConversationFlow,
            attachments: AIChat.Attachments = .photoLibrary,
            rating: AIChat.Rating = .enabled,
            appearancePreference: AIChat.Appearance = .system,
            onClose: (() -> Void)? = nil,
            onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)? = nil,
            onLivechatSessionChange: (@MainActor (AIChat.LivechatSessionInfo) -> Void)? = nil,
            ratingSession: RatingSession = RatingSession(),
            makeProvider: @escaping ProviderFactory = { service, pageContext, welcome, acceptsUploadPrompts, acceptsHumanAgentPrompts in
                ChatProvider(
                    service: service,
                    pageContext: pageContext,
                    welcomeMessage: welcome,
                    acceptsImageUploadPrompts: acceptsUploadPrompts,
                    acceptsHumanAgentPrompts: acceptsHumanAgentPrompts
                )
            },
            encodeAttachment: AttachmentEncoder? = nil,
            submitAction: ActionSubmitter? = nil,
            rateConversation: RatingSubmitter? = nil,
            submitLivechatFeedback: LivechatFeedbackSubmitter? = nil,
            fetchForm: FormFetcher? = nil,
            fetchSession: SessionFetcher? = nil,
            patchFormValues: FormValuesPatcher? = nil,
            submittedForms: SubmittedFormStore = SubmittedFormStore()
        ) {
            self.service = service
            self.pageContext = { await contextProvider?() }
            self.conversationFlow = conversationFlow
            self.attachments = attachments
            self.rating = rating
            self.appearancePreference = appearancePreference
            self.onClose = onClose
            self.onAddToCart = onAddToCart
            self.onLivechatSessionChange = onLivechatSessionChange
            self.ratingSession = ratingSession
            self.makeProvider = makeProvider
            // Not `??`: the 6.x frontend crashes lowering a typed-throws function value inside
            // the `??` autoclosure.
            if let encodeAttachment {
                self.encodeAttachment = encodeAttachment
            } else {
                self.encodeAttachment = { data, options throws(ImageAttachment.Failure) in
                    try ImageAttachment.encode(data, options: options)
                }
            }
            self.submitAction = submitAction ?? { request in
                try await service.submitAction(request)
            }
            self.rateConversation = rateConversation ?? { request in
                try await service.rateConversation(request)
            }
            self.submitLivechatFeedbackRequest = submitLivechatFeedback ?? { request in
                try await service.submitLivechatFeedback(request)
            }
            self.fetchForm = fetchForm ?? { id in
                try await service.fetchForm(id: id)
            }
            self.fetchSession = fetchSession ?? {
                try await service.fetchSession()
            }
            self.patchFormValues = patchFormValues ?? { formId, values in
                try await service.patchFormValues(formId: formId, values: values)
            }
            self.submittedForms = submittedForms
            // Product/table imagery fills ~half-width, ~800px covers 3x.
            self.imageLoader = ImageLoader(maxPixelSize: 800) { try await service.fetchData($0) }
        }

        /// Returns the cached draft for `form`, creating one on first access. A form this
        /// device already submitted (per ``SubmittedFormStore``) starts collapsed.
        func formModel(for form: ConversationForm) -> FormSubmissionModel {
            if let existing = self.formModels[form.partId] {
                return existing
            }
            let model = FormSubmissionModel(
                form: form,
                submittedConfirmation: self.submittedForms.confirmation(for: form.partId)
            )
            self.formModels[form.partId] = model
            return model
        }

        /// Lookup by `partId` only — used when routing a photo pick back to a form.
        func formModel(forPartId partId: String) -> FormSubmissionModel? {
            self.formModels[partId]
        }

        /// Validates and submits the form identified by `partId`. Surfaces session expiry;
        /// other failures land on the form card. A no-op for unknown ids, drafts that fail
        /// validation, and forms already submitting or submitted.
        func submitForm(partId: String) async throws(SessionEnded) {
            guard let model = self.formModels[partId], !model.isSubmitting, !model.isSubmitted else { return }
            guard model.validate() else { return }
            guard let request = model.buildRequest() else {
                model.markFailed()
                return
            }
            guard model.beginSubmitting() else { return }

            do {
                let response = try await self.submitAction(request)
                let text = Self.confirmationText(server: response.confirmationText, form: model.form)
                self.submittedForms.record(partId: partId, confirmation: text)
                model.markSubmitted(confirmation: text)
                // Server already created/reused the session via start_livechat — poll, don't handover.
                if response.livechatSession?.shouldAdoptPoller == true {
                    await self.adoptLivechatSessionAfterFormSubmit()
                }
            } catch let error as ChatServiceError {
                switch error {
                case .sessionExpired:
                    model.markFailed()
                    throw SessionEnded()
                case .validation(let message, let params):
                    model.applyServerErrors(params: params, formMessage: message)
                default:
                    model.markFailed()
                }
            } catch {
                model.markFailed()
            }
        }

        /// Server → inline marker copy → SDK default, skipping blank server text.
        static func confirmationText(server: String?, form: ConversationForm) -> String {
            let trimmed = server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
            return form.confirmationText ?? L10n.formSubmittedDefault.string
        }

        /// Starts a fresh rating draft for the overlay. Call when presenting.
        func beginRating() -> RatingSubmissionModel {
            let model = RatingSubmissionModel()
            self.ratingModel = model
            return model
        }

        /// Drops the in-flight rating draft (after dismiss / skip / success).
        func endRating() {
            self.ratingModel = nil
        }

        /// Submits `score` (1–5) with optional feedback. Marks the session rated on success
        /// so a later close does not re-ask. Surfaces session expiry; other failures stay on
        /// the overlay for retry.
        func submitRating(score: Int, feedback: String?) async throws(SessionEnded) {
            guard let model = self.ratingModel else { return }
            guard model.beginSubmitting(score: score, feedback: feedback) else { return }

            do {
                try await self.rateConversation(RateConversationRequest(rating: score, feedback: feedback))
                self.ratingSession.markRated()
                self.ratingModel = nil
            } catch let error as ChatServiceError {
                if case .sessionExpired = error {
                    model.markFailed(message: L10n.ratingFailed.string)
                    throw SessionEnded()
                }
                model.markFailed(message: L10n.ratingFailed.string)
            } catch {
                model.markFailed(message: L10n.ratingFailed.string)
            }
        }

        /// Chat Close: skip-in-place when the livechat CSAT overlay is up, else last-chance CSAT
        /// when closed + pending, else conversation `/rate`, else hand off. Does **not** call `onClose`.
        func prepareClose(showingLivechatCSAT: Bool) -> CloseDecision {
            if showingLivechatCSAT {
                self.dismissLivechatCSAT()
                return .handoffToHost
            }
            if self.canOfferLivechatCSAT {
                self.offerLivechatCSATIfNeeded(feedbackPending: true)
                return .presentLivechatCSAT
            }
            if self.shouldOfferRating {
                return .presentConversationRating
            }
            return .handoffToHost
        }

        /// Submits livechat CSAT. Does **not** mark ``RatingSession`` or call `onClose`.
        /// A 409 after a closed + pending present is treated as success (already submitted
        /// or a close/handover race). Other transport errors keep the draft for retry.
        func submitLivechatFeedback(score: Int, feedback: String?) async throws(SessionEnded) {
            guard let model = self.ratingModel else { return }
            guard model.beginSubmitting(score: score, feedback: feedback) else { return }

            do {
                _ = try await self.submitLivechatFeedbackRequest(
                    RateConversationRequest(rating: score, feedback: feedback)
                )
                self.finishLivechatCSAT()
            } catch let error as ChatServiceError {
                switch error {
                case .sessionExpired:
                    model.markFailed(message: L10n.ratingFailed.string)
                    throw SessionEnded()
                case .conflict:
                    // Already submitted — treat as success so the overlay dismisses.
                    self.finishLivechatCSAT()
                default:
                    model.markFailed(message: L10n.ratingFailed.string)
                }
            } catch {
                model.markFailed(message: L10n.ratingFailed.string)
            }
        }

        /// Scale Skip / backdrop for livechat CSAT — no POST; stay in chat.
        func dismissLivechatCSAT() {
            self.dismissedLivechatFeedback = true
            self.livechatCSATPending = false
            self.ratingModel = nil
        }

        /// Clears the pending flag after `ChatView` presents the overlay.
        func consumeLivechatCSATPending() {
            self.livechatCSATPending = false
        }

        /// Waiting/active — drop any CSAT draft (no POST) and allow CSAT again on the next close.
        func resetLivechatCSATDismiss() {
            self.dismissedLivechatFeedback = false
            self.livechatCSATPending = false
            self.ratingModel = nil
        }

        /// Closed + `feedback.pending` (bootstrap, closed edge, or Chat Close) — ask `ChatView`
        /// to present CSAT. Not a closed-edge-only trigger.
        func offerLivechatCSATIfNeeded(feedbackPending: Bool) {
            guard feedbackPending, !self.dismissedLivechatFeedback else { return }
            self.livechatCSATPending = true
        }

        private func finishLivechatCSAT() {
            self.dismissedLivechatFeedback = true
            self.livechatCSATPending = false
            self.livechat.markFeedbackSubmitted()
            self.ratingModel = nil
        }

        /// Encodes a picked photo for a form file field or a ticket attachment. `maxBytes` is
        /// the decoded-size budget from the marker (2 MiB by contract). Failures surface as the
        /// same notices the composer shows; the result is `nil` in that case.
        func ingestFormPhoto(
            _ data: Data,
            maxBytes: Int,
            filename: String
        ) async -> PendingAttachment? {
            await self.encode(data, options: .action(filename: filename, maxDecodedBytes: maxBytes))
        }

        /// Bootstraps once, then no-ops on re-entry
        /// (e.g. the view reappearing) so the live session survives.
        func start() async {
            // SwiftUI may recreate `ChatView` (cancelling `.task`) after `provider` is
            // attached but before `phase` flips to `.ready`. A naïve `provider == nil`
            // guard then no-ops forever on a blank loading screen even though config and
            // history already landed. Recover that half-finished bootstrap.
            if self.phase == .ready { return }
            if self.provider != nil {
                self.phase = .ready
                return
            }
            await self.bootstrap()
        }

        /// Test seam — installs a ready provider without config bootstrap so send paths and
        /// snapshot-derived state can be exercised with ``MockChatService`` / a stub ``ChatProviding``.
        func attachProviderForTesting(_ provider: any ChatProviding) {
            self.provider = provider
            self.observe(provider)
            self.phase = .ready
        }

        /// Test seam — sets the filtered start-prompt list without going through `/config`.
        func setStartPromptsForTesting(_ prompts: [StartPrompt]) {
            self.startPrompts = prompts
        }

        /// Filters config rows for the current page — the same path `bootstrap()` uses after
        /// awaiting `contextProvider` once. Matching is a literal substring of that page string
        /// against each `url_pattern`; it does not re-run on send.
        func applyStartPromptsFromConfig(_ prompts: [StartPrompt], page: String?) {
            self.startPrompts = StartPromptMatching.select(prompts, page: page)
        }

        /// Fetches in-chat banners for `page`. Soft-fails to an empty list on transport /
        /// missing-route / decode so an older API does not brick bootstrap. A 401
        /// surfaces as ``SessionEnded`` (same path as send / export).
        func loadBanners(url: String?) async throws(SessionEnded) {
            do {
                self.banners = try await self.service.fetchBanners(url: url)
            } catch ChatServiceError.sessionExpired {
                self.banners = []
                self.sessionEnded = true
                throw SessionEnded()
            } catch {
                self.banners = []
            }
        }

        /// Test seam — installs banners without hitting the network.
        func setBannersForTesting(_ banners: [ChatBanner]) {
            self.banners = banners
        }

        /// Hides a dismissible banner for the rest of this session (content fingerprint).
        func dismissBanner(_ banner: ChatBanner) {
            self.dismissedBannerFingerprints.insert(banner.contentFingerprint)
        }

        /// Copies `/config` `image_enabled` — call before ``makeProvider`` so upload-prompt
        /// ingestion sees the same gate as the composer button.
        func applyImageEnabledFromConfig(_ enabled: Bool) {
            self.chatbotImageEnabled = enabled
        }

        /// Copies product-card settings from `/config`. The cart button also needs ``onAddToCart``
        /// and a per-card sku (see ``ProductGridView/shouldOfferCart(for:onAddToCart:)``).
        func applyProductCardFromConfig(_ settings: ProductCardSettings) {
            self.productOpenLabel = settings.openLabel
            self.showsAddToCart = settings.addToCart.enabled && self.onAddToCart != nil
        }

        /// Test seam — sets product-card CTA state without going through `/config`.
        func setProductCardForTesting(openLabel: String?, addToCartEnabled: Bool) {
            self.applyProductCardFromConfig(
                ProductCardSettings(openLabel: openLabel, addToCartEnabled: addToCartEnabled)
            )
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
                let page = await self.pageContext()
                self.applyStartPromptsFromConfig(config.startPrompts, page: page)
                // 401 sets `sessionEnded` then throws; swallow so bootstrap can
                // reach ready chrome and ChatView can present the session-ended alert.
                try? await self.loadBanners(url: page)
                self.applyProductCardFromConfig(config.productCard)
                self.applyLivechatFromConfig(config.livechat)
                self.applyWaitingFormIdFromConfig(config.livechatWaitingFormId)
                self.applyImageEnabledFromConfig(config.imageEnabled)

                let provider = self.makeProvider(
                    self.service,
                    self.pageContext,
                    config.display.welcomeMessage,
                    self.offersAttachments,
                    config.livechat.isAvailable
                )

                self.provider = provider
                self.observe(provider)

                // Flip to ready before history so a cancelled `.task` mid-`loadOlder` still
                // leaves the chrome on screen; history fills in when the load finishes.
                self.phase = .ready
                _ = try? await provider.loadOlder()
                await self.bootstrapLivechatIfNeeded()

            } catch {
                self.phase = .failed
            }
        }

        /// Sends a user message (draft text and any pending attachments). Recoverable failures
        /// (busy, retryable) bounce inline as a notice so the input stays stateless; a 401 ends
        /// the session and escapes as ``SessionEnded`` for the view to alert on.
        func send() async throws(SessionEnded) {
            let text = self.currentMessage
            let attachments = self.pendingAttachments
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasText || !attachments.isEmpty else { return }

            self.endTypingIfNeeded()
            self.currentMessage = ""
            self.pendingAttachments = []
            // The echo renders each photo from its data URL; hand the loader the bitmap we already
            // decoded so the user pane never round-trips base64 → ImageIO for its own upload.
            for pending in attachments {
                if let url = pending.attachment.dataURL {
                    await self.imageLoader.store(pending.thumbnail, for: url)
                }
            }
            if let bounced = try await self.deliver(
                text,
                attachments: attachments.map(\.attachment)
            ) {
                self.currentMessage = bounced
                // A photo picked while the send was in flight is the newer intent; the bounced
                // ones go back in front of it and the cap trims from the oldest end.
                self.pendingAttachments = Self.capped(attachments + self.pendingAttachments)
            }
        }

        /// Sends a suggestion-card or start-prompt chip's text. Leaves the composer draft
        /// untouched — there is no draft to restore on a bounce, so recoverable failures only
        /// surface the existing notice.
        func send(prompt: String) async throws(SessionEnded) {
            let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            _ = try await self.deliver(text, attachments: [])
        }

        /// Encodes a picked photo into a pending attachment chip, dropping the oldest chip once
        /// ``maxPendingAttachments`` is reached. Failures surface as a bottom notice; the picker
        /// selection is cleared by the caller regardless.
        ///
        /// No filename is attached on purpose: `PhotosPickerItem` exposes only an asset identifier,
        /// which is neither a name nor something the backend should see. The API omits the caption
        /// when `filename` is absent, and the chip is labelled generically.
        ///
        /// Encode budget follows `/config` `livechat.max_attachment_size_bytes` when the chip
        /// may later POST to `/livechat/messages` (waiting or active, `attachments_enabled`).
        func ingestPickedPhoto(_ data: Data) async {
            let livechatDecoded: Int? =
                self.livechat.attachmentsEnabled && self.livechat.isInSession
                ? self.livechat.maxAttachmentSizeBytes
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

        /// The one encode path for every photo destination: runs the injected encoder off the
        /// main actor, flags `isEncodingAttachment` meanwhile, and maps failures to notices.
        private func encode(_ data: Data, options: ImageAttachment.Options) async -> PendingAttachment? {
            self.isEncodingAttachment = true
            defer { self.isEncodingAttachment = false }

            do {
                let encoded = try await Task.detached(priority: .userInitiated) { [encode = self.encodeAttachment] in
                    try encode(data, options)
                }.value
                return PendingAttachment(
                    thumbnail: Image(decorative: encoded.thumbnail, scale: 1),
                    attachment: encoded.attachment,
                    displayName: L10n.mediaImageLabel.string
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

        /// Shared delivery for composer and suggestion taps.
        /// Returns text to restore into the composer on a recoverable bounce; `nil` otherwise.
        /// Attachments are restored by the composer `send()` from its own captured copy.
        private func deliver(
            _ text: String,
            attachments: [OutgoingAttachment]
        ) async throws(SessionEnded) -> String? {
            if self.notice?.edge == .bottom { self.dismissNotice() }
            guard let provider = self.provider else { return nil }

            do {
                if self.livechat.status == .active {
                    try await provider.sendLivechat(text, attachments: attachments)
                } else {
                    try await provider.send(text, attachments: attachments)
                }
                return nil

            } catch {
                switch error {
                case .busy(.streaming):
                    self.present(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))
                    return text

                case .busy(.operation):
                    // A reset / delete is in flight (sub-second). Give the draft back rather than
                    // drop a picked photo on the floor; the operation's own UI covers the wait.
                    return text

                case .retry(popped: let lastMessage, body: let body):
                    self.present(Notice(edge: .bottom, message: body ?? L10n.noticeSendFailed.string, autoDismiss: nil))
                    return lastMessage

                case .conflict(popped: let popped):
                    // Race: session just went active. Flip, start polling, and re-route.
                    await self.resumeLivechatAfterConflict()
                    do {
                        try await provider.sendLivechat(popped, attachments: attachments)
                        return nil
                    } catch {
                        switch error {
                        case .sessionExpired:
                            throw SessionEnded()
                        case .livechatInactive(popped: let text):
                            return try await self.rerouteToAIAfterLivechatInactive(
                                text,
                                attachments: attachments,
                                provider: provider
                            )
                        default:
                            self.present(Notice(
                                edge: .bottom,
                                message: L10n.noticeSendFailed.string,
                                autoDismiss: nil
                            ))
                            return popped
                        }
                    }

                case .livechatInactive(popped: let popped):
                    return try await self.rerouteToAIAfterLivechatInactive(
                        popped,
                        attachments: attachments,
                        provider: provider
                    )

                case .sessionExpired:
                    throw SessionEnded()
                }
            }
        }

        /// Loads the next older page of history. A recoverable failure is reported as
        /// ``HistoryLoadOutcome/failed`` rather than as a notice — the conversation list shows it
        /// inline at the top edge with a retry, where the reader is looking. A 401 ends the
        /// session and escapes as ``SessionEnded`` for the view to alert on.
        @discardableResult
        func loadOlder() async throws(SessionEnded) -> HistoryLoadOutcome {
            do {
                let prepended = try await self.provider?.loadOlder() ?? false
                return prepended ? .prepended : .nothing

            } catch ChatServiceError.sessionExpired {
                throw SessionEnded()

            } catch is CancellationError {
                // The view's load task was torn down mid-flight; nothing to retry.
                return .nothing

            } catch let error as URLError where error.code == .cancelled {
                return .nothing

            } catch {
                return .failed
            }
        }

        /// Resets the conversation.
        func reset() async {
            do {
                try await self.provider?.reset()
            } catch {
                // Provider leaves the conversation intact on failure — keep drafts and
                // submitted part ids so the still-current chat can re-open those forms.
                self.presentNotice(Notice(
                    edge: .bottom,
                    message: L10n.noticeSendFailed.string,
                    autoDismiss: .seconds(4)
                ))
                return
            }
            // The old conversation's forms are gone with it; drop their drafts and
            // persisted part ids — the new conversation cannot reference them.
            self.formModels = [:]
            self.submittedForms.removeAll()
            self.ratingSession.clear()
            self.ratingModel = nil
            self.clearWaitingForm()
            await self.teardownLivechat()
            if !self.suppressLivechatNetwork, let config = try? await self.service.fetchConfig() {
                self.applyLivechatFromConfig(config.livechat)
                self.applyWaitingFormIdFromConfig(config.livechatWaitingFormId)
            }
            await self.bootstrapLivechatIfNeeded()
        }

        /// Request deletion of visitor data and end the session. Rethrows so the delete sheet can act on the
        /// hook's suspension point — success dismisses it, a failure leaves it open for the host.
        func delete() async throws(DeletionFailed) {
            do {
                try await self.provider?.delete()
            } catch {
                throw DeletionFailed()
            }
            // Visitor data deletion covers what this device remembers about their forms too.
            self.formModels = [:]
            self.submittedForms.removeAll()
            self.ratingSession.clear()
            self.ratingModel = nil
            self.clearWaitingForm()
            await self.teardownLivechat()
        }

        /// Single temp path for the GDPR export. Overwritten on each download; deleted when
        /// Privacy dismisses or the share sheet completes.
        static let exportFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diverge-export.json")

        /// Writes the GDPR export JSON to the stable temp file and returns its URL.
        /// Does not clear the conversation. A 401 surfaces as ``SessionEnded``.
        func exportMyData() async throws -> URL {
            guard let provider = self.provider else { throw ExportFailed() }
            do {
                let data = try await provider.exportMyData()
                guard
                    let object = try? JSONSerialization.jsonObject(with: data),
                    object is [String: Any]
                else {
                    throw ExportFailed()
                }
                var options: Data.WritingOptions = .atomic
#if os(iOS)
                options.insert(.completeFileProtection)
#endif
                try data.write(to: Self.exportFileURL, options: options)
                return Self.exportFileURL
            } catch is SessionEnded {
                throw SessionEnded()
            } catch ChatServiceError.sessionExpired {
                throw SessionEnded()
            } catch {
                throw ExportFailed()
            }
        }

        /// Removes the temp export file so PII does not sit in the container after share / dismiss.
        func discardExportFile() {
            try? FileManager.default.removeItem(at: Self.exportFileURL)
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

        /// Mirrors the provider's latest-wins snapshots onto the main actor.
        private func observe(_ provider: some ChatProviding) {
            let stream = provider.stream
            Task { [weak self] in
                for await snapshot in stream {
                    self?.snapshot = snapshot
                }
            }
        }

        private func present(_ notice: Notice) {
            self.presentNotice(notice)
        }

        /// Shared by livechat and other surfaces that live in sibling files.
        func presentNotice(_ notice: Notice) {
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

        /// Surfaces a generic attachment-load failure from the view (picker / transferable miss).
        func presentAttachmentFailure() {
            self.present(Notice(
                edge: .bottom,
                message: L10n.attachmentFailed.string,
                autoDismiss: .seconds(4)
            ))
        }
    }
}
