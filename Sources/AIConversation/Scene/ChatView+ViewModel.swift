//
//  ChatView+ViewModel.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import AIConversationEngine

extension ChatView {

    /// Observable state for the main screen. Coordinates the chat service facade.
    ///
    /// Behaviour lives in sibling extension files — `+Config` (bootstrap, `/config` appliers,
    /// banners), `+Send` (delivery, history paging, reset / delete), `+Attachments` (photo
    /// encode) and `+Export` (GDPR download). Stored state is declared here; it is internal
    /// rather than `private(set)` so those extensions can mutate it — nothing outside the
    /// view model should write to it.
    @MainActor
    @Observable
    final class ViewModel {

        enum Phase {
            case loading, ready, failed
        }

        /// Builds the session data layer. Defaults to ``ChatProvider``; tests inject a stub.
        /// Arguments: service, page context, welcome message, whether upload prompts render.
        typealias ProviderFactory = (
            any ChatServicing,
            @escaping @Sendable () async -> String?,
            String?,
            Bool
        ) -> any ChatProviding

        /// Turns picked photo bytes into a wire attachment for the given destination. Defaults to
        /// ``ImageAttachment/encode(_:options:)``; tests inject a stub to drive the failure paths.
        typealias AttachmentEncoder = @Sendable (
            Data,
            ImageAttachment.Options
        ) throws(ImageAttachment.Failure) -> ImageAttachment.Encoded

        /// How many photos may ride along with one message. The strip, bounce restore, and wire
        /// path already handle N; 8 is the UX cap so a long chip row stays usable.
        static let maxPendingAttachments = 8

        // MARK: State (written by the ViewModel extensions only)

        var phase: Phase = .loading
        var appearance: ChatAppearance?

        var name = ""
        var subtitle: Subtitle?
        var privacyPolicyURL: URL?
        var avatar: Image?
        var logo: HeaderLogo?
        var notice: Notice?
        /// Filtered starter chips for the current page context (empty when none / already chatting).
        var startPrompts: [StartPrompt] = []
        /// Active in-chat promo banners from `GET /api/v1/chat/banners` (empty when none / soft-fail).
        var banners: [ChatBanner] = []
        /// In-memory dismiss keys (content fingerprints) for this ``AIChat`` session.
        var dismissedBannerFingerprints: Set<String> = []
        /// Set when a session-bound call (banners 401) expires the visitor token.
        /// ``ChatView`` presents the same session-ended alert as send / export.
        var sessionEnded = false
        /// Dashboard open-product CTA label; `nil` → localised ``L10n/productOpen`` at the view.
        var productOpenLabel: String?
        /// Whether `/config` `product_card.add_to_cart.enabled` is on. Gates **both** cart modes:
        /// the host callback and link-mode `add_to_cart.url` — a card URL alone must not surface
        /// a cart button on a chatbot whose dashboard has cart switched off.
        var cartEnabledByConfig = false
        /// From `/config` `image_enabled`. Omitted APIs leave this `true` so the host gate is the
        /// only switch. Host ``AIChat/Attachments/disabled`` still wins.
        var chatbotImageEnabled = true

        var snapshot: ConversationSnapshot?
        var currentMessage = ""
        /// Photos waiting to ride along with the next send (at most ``maxPendingAttachments``).
        /// Restored on a recoverable bounce.
        var pendingAttachments: [PendingAttachment] = []
        /// True while a picked photo is being downsampled / encoded.
        var isEncodingAttachment = false

        // MARK: Host configuration

        /// Shared loader for remote imagery injected into the view environment.
        @ObservationIgnored let imageLoader: ImageLoader
        @ObservationIgnored let conversationFlow: AIChat.ConversationFlow
        /// Which attachment sources the composer offers — host-configured, see ``AIChat/Attachments``.
        @ObservationIgnored let attachments: AIChat.Attachments
        /// Palette selection — host-configured, see ``AIChat/Appearance``.
        @ObservationIgnored let appearancePreference: AIChat.Appearance
        /// Host dismiss hook. Non-`nil` enables the SDK close button.
        @ObservationIgnored let onClose: (() -> Void)?
        /// Host cart hook. Combined with config `product_card.add_to_cart.enabled` for the cart button.
        @ObservationIgnored let onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)?
        @ObservationIgnored let service: ChatService
        /// Per-message page string.
        @ObservationIgnored let pageContext: @Sendable () async -> String?
        @ObservationIgnored let makeProvider: ProviderFactory
        @ObservationIgnored let encodeAttachment: AttachmentEncoder
        @ObservationIgnored var provider: (any ChatProviding)?

        // MARK: Derived state

        /// Whether `/config` enabled add-to-cart **and** the host supplied ``onAddToCart``.
        /// Per-card sku is applied in ``ProductGridView/shouldOfferCart(for:cartEnabled:onAddToCart:)``.
        var showsAddToCart: Bool {
            self.cartEnabledByConfig && self.onAddToCart != nil
        }

        /// Config+hook gate for the grid; `nil` when cart is off so the view takes one optional.
        var productAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)? {
            self.showsAddToCart ? self.onAddToCart : nil
        }

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

        /// Composer placeholder.
        var inputPlaceholder: String {
            L10n.inputPlaceholder.string
        }

        /// Whether a response in the given bot turn is still actionable (quick replies, etc.) —
        /// only the newest bot turn.
        func isLatestBotTurn(_ turnID: UUID) -> Bool {
            self.snapshot?.lastBotTurnID == turnID
        }

        /// True when the host provided ``AIChat/Configuration/onClose`` — the close button only
        /// renders then, so integrators who do not adopt the hook see today's behaviour.
        var showsCloseButton: Bool {
            self.onClose != nil
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

        // MARK: Lifecycle

        init(
            service: ChatService,
            contextProvider: (@Sendable () async -> String?)?,
            conversationFlow: AIChat.ConversationFlow,
            attachments: AIChat.Attachments = .photoLibrary,
            appearancePreference: AIChat.Appearance = .system,
            onClose: (() -> Void)? = nil,
            onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)? = nil,
            makeProvider: @escaping ProviderFactory = { service, pageContext, welcome, acceptsUploadPrompts in
                ChatProvider(
                    service: service,
                    pageContext: pageContext,
                    welcomeMessage: welcome,
                    acceptsImageUploadPrompts: acceptsUploadPrompts
                )
            },
            encodeAttachment: AttachmentEncoder? = nil
        ) {
            self.service = service
            self.pageContext = { await contextProvider?() }
            self.conversationFlow = conversationFlow
            self.attachments = attachments
            self.appearancePreference = appearancePreference
            self.onClose = onClose
            self.onAddToCart = onAddToCart
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
            // Product/table imagery fills ~half-width, ~800px covers 3x.
            self.imageLoader = ImageLoader(maxPixelSize: 800) { try await service.fetchData($0) }
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

        /// Mirrors the provider's latest-wins snapshots onto the main actor.
        func observe(_ provider: some ChatProviding) {
            let stream = provider.stream
            Task { [weak self] in
                for await snapshot in stream {
                    self?.snapshot = snapshot
                }
            }
        }

        // MARK: Notices

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
    }
}
