//
//  AIChat.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import SwiftUI
import AIConversationEngine
#if canImport(UIKit)
import UIKit
#endif

/// Chatbot API host constants. ``AIChat/Configuration`` defaults to ``productionBaseURL``.
/// Development and local hosts belong in the host/sample build config — not the public SDK surface.
public enum DivergeAPI {
    /// Live production API. Single source of truth shared with the engine facade.
    public static let productionBaseURL = ChatService.productionBaseURL
}

/// Public entry point for the conversational-search chat SDK.
///
/// Configure it with a ``Configuration`` of host-provided hooks.
/// Mint the chat UI with ``makeView()`` / ``makeViewController()``.
/// The conversation session lives as long as the instance that
/// produced the view, so the caller owns the instance.
///
/// Two equivalent ways to construct it:
/// ```swift
/// // Shared config, registered once (typically at launch):
/// AIChat.configure(.init(tokenProvider: { ... }, resetConversation: { ... }, deleteData: { ... }))
/// let chat = AIChat()
///
/// // Or direct:
/// let chat = AIChat(.init(tokenProvider: { ... }, resetConversation: { ... }, deleteData: { ... }))
/// ```
///
/// The SDK never sees the API key and does not persist the token to disk.
/// Session continuity across launches is the host's responsibility.
@MainActor
public final class AIChat {

    private static var sharedConfiguration: Configuration?

    private let configuration: Configuration
    private let service: ChatService
    /// Survives host dismiss / re-present — `makeView()` builds a fresh view model each time.
    private let ratingSession: RatingSession
    /// Reused across `makeView()` calls so SwiftUI body re-evals do not re-bootstrap mid-presentation.
    private var hostedViewModel: ChatView.ViewModel?

    /// Registers shared configuration for the no-argument ``init()``. Stores the config
    /// only — it neither returns nor retains an instance. Call once, typically at launch.
    public static func configure(_ configuration: Configuration) {
        Self.sharedConfiguration = configuration
    }

    /// Direct initialisation — equivalent to ``configure(_:)`` followed by ``init()``.
    public init(_ configuration: Configuration) {
        self.configuration = configuration
        // The  hooks wire straight to the service / token store.
        self.service = ChatService(
            tokenProvider: configuration.tokenProvider,
            onResetConversation: configuration.resetConversation,
            onDeleteData: configuration.deleteData,
            baseURL: configuration.apiBaseURL
        )
        self.ratingSession = RatingSession()
    }

    /// Picks up the configuration registered via ``configure(_:)``. Calling this before
    /// `configure()` is a programmer error and traps.
    public convenience init() {
        guard let configuration = Self.sharedConfiguration else {
            preconditionFailure("AIChat() requires AIChat.configure(_:) to be called first.")
        }
        self.init(configuration)
    }
}

public extension AIChat {

    /// The chat UI as a SwiftUI view. The session is tied to this instance;
    /// presentation (sheet, cover, push) is the caller's responsibility.
    ///
    /// ``Configuration/appearance``, ``Configuration/attachments`` and ``Configuration/rating``
    /// are captured on the first call. Mint a new ``AIChat`` to change them.
    func makeView() -> some View {
        let viewModel: ChatView.ViewModel
        if let hostedViewModel {
            viewModel = hostedViewModel
        } else {
            viewModel = ChatView.ViewModel(
                service: self.service,
                contextProvider: self.configuration.contextProvider,
                conversationFlow: self.configuration.conversationFlow,
                attachments: self.configuration.attachments,
                rating: self.configuration.rating,
                appearancePreference: self.configuration.appearance,
                onClose: self.configuration.onClose,
                onAddToCart: self.configuration.onAddToCart,
                onLivechatSessionChange: self.configuration.onLivechatSessionChange,
                ratingSession: self.ratingSession
            )
            self.hostedViewModel = viewModel
        }
        return ChatView(viewModel: viewModel)
            .environment(\.openURL, self.openURL)
    }

#if canImport(UIKit)
    /// The chat UI wrapped in a hosting controller, for UIKit callers.
    /// presentation (sheet, cover, push) is the caller's responsibility.
    func makeViewController() -> UIHostingController<some View> {
        let controller = UIHostingController(rootView: self.makeView())
        controller.sheetPresentationController?.prefersGrabberVisible = true
        return controller
    }
#endif

    private var openURL: OpenURLAction {
        OpenURLAction { url in
            guard let onOpenLink = self.configuration.onOpenLink else { return .systemAction }
            onOpenLink(url)
            return .handled
        }
    }
}

public extension AIChat {

    /// The direction the conversation flows.
    enum ConversationFlow {
        /// A send lifts the user turn to the top and the reply free-flows into the space beneath it.
        case topDown
        /// Classic chat: new turns land at the bottom and the list follows the newest.
        case bottomUp
    }

    /// Which attachment sources the composer offers the visitor.
    ///
    /// Photo attach also requires `/config` `image_enabled` (omitted on older APIs is treated as
    /// enabled). ``disabled`` always wins — use it to hide attach even when the chatbot allows
    /// images.
    enum Attachments: Sendable {
        /// No attach control — text only.
        case disabled
        /// A photo-library picker (`PhotosPicker`, out-of-process — no photo permission prompt).
        /// Up to eight photos per message; each is downsampled and re-encoded as JPEG,
        /// which also drops the photo's metadata (GPS location, capture time, device make / model —
        /// only pixel dimensions remain). Chip thumbnails are a separate ~170 px downsample.
        case photoLibrary
    }

    /// Whether the SDK offers a **conversation** rating prompt (`POST /rate`) when the visitor
    /// taps close.
    ///
    /// The public `/config` response has no rating-enabled flag, so the host decides.
    /// The close button itself only appears when
    /// ``Configuration/onClose`` is set; this flag controls the conversation prompt, not the
    /// button. Livechat CSAT (`POST /livechat/feedback` when `feedback.pending`) is gated by
    /// the server, not this flag.
    enum Rating: Sendable {
        /// Show the 1–5 rating overlay on close when the conversation has a user turn and has
        /// not been rated yet.
        case enabled
        /// Close immediately without asking.
        case disabled
    }

    /// Which `/config` palette slot the chat paints.
    ///
    /// `.dark` means “use the `dark_theme` slot”, not “invent a dark look”. When a chatbot
    /// has no dark theme the server clones light into `dark_theme`, so the chat stays
    /// visually light under `.system` (in Dark Mode) and under `.dark`. System chrome
    /// (keyboard, pickers) follows the **painted** palette, not this lock alone.
    ///
    /// Captured on the first ``AIChat/makeView()``. Mint a new ``AIChat`` to change it
    /// (same as ``Attachments`` and ``Rating``). There is no in-chat theme toggle.
    enum Appearance: Sendable {
        /// Follow the environment color scheme (default).
        case system
        /// Always the config's light `theme`.
        case light
        /// Always the config's `dark_theme` slot (light when that slot is a clone).
        case dark
    }

    /// Identity of a product the visitor wants to add to their cart.
    ///
    /// Handed to ``Configuration/onAddToCart``. `id` is the product identifier — a catalog id
    /// when the source supplies one, otherwise a parser-derived stand-in (URL slug or
    /// `url:title`). `sku` is the commerce SKU from a `{{add_to_cart:SKU}}` marker (or JSON
    /// field); treat it as untrusted input and validate it against your catalog before calling a
    /// cart API. The SDK does not show "added" feedback — the host owns toasts / cart UI.
    struct ProductSelection: Sendable, Equatable {
        public let id: String
        public let sku: String
        public let title: String
        public let url: URL

        public init(id: String, sku: String, title: String, url: URL) {
            self.id = id
            self.sku = sku
            self.title = title
            self.url = url
        }
    }

    /// The host-provided hooks the SDK is configured with. This is the single injection
    /// surface,  both ``AIChat/configure(_:)`` and ``AIChat/init(_:)`` take it.
    ///
    /// The three hooks (`tokenProvider`, `resetConversation`, `deleteData`) are required —
    /// the SDK is not correctly configured without them (Control Plane: Identity, Minting, Invalidation).
    /// SDK is pure (Data plane) to avoid split Token Ownership, Distributed State with Async Reconciliation and Structural Inversion.
    ///
    /// The enhancement hooks (`contextProvider`, `onOpenLink`, `onClose`, `onAddToCart`,
    /// `onLivechatSessionChange`) are optional and degrade gracefully when omitted.
    struct Configuration {

        let tokenProvider: @Sendable () async throws -> String
        let resetConversation: @Sendable () async throws -> String
        let deleteData: @Sendable () async throws -> Void
        let contextProvider: (@Sendable () async -> String?)?
        let onOpenLink: ((URL) -> Void)?
        /// Called after the visitor rates or skips (or when rating is disabled / not offered).
        /// When non-`nil`, the SDK shows a close button that eventually invokes this so the
        /// host can dismiss. Absent → no close button (host owns dismissal exclusively).
        let onClose: (() -> Void)?
        /// Receives an add-to-cart tap on a product card. The cart button only appears when this
        /// is set, `/config` reports `product_card.add_to_cart.enabled`, **and** the card carries
        /// a sku. Absent → no cart button. Invoked on the main actor; the SDK does not show
        /// add-to-cart feedback (toast / "Added" is host-owned).
        let onAddToCart: (@MainActor (ProductSelection) -> Void)?
        /// Fires when livechat **status** or active **agent name** changes (not typing / messages).
        /// Absent → no-op. The poller still parks when the chat is off-screen or backgrounded;
        /// the last value is the host’s to keep for a launcher badge after dismiss.
        let onLivechatSessionChange: (@MainActor (LivechatSessionInfo) -> Void)?
        let conversationFlow: ConversationFlow
        /// Chatbot API host. Defaults to ``DivergeAPI/productionBaseURL``.
        /// Pass a non-production URL from the host or sample build settings while integrating.
        let apiBaseURL: URL
        /// Attachment sources offered in the composer. Defaults to ``Attachments/photoLibrary``.
        let attachments: Attachments
        /// Whether to prompt for a rating on close. Defaults to ``Rating/enabled``.
        let rating: Rating
        /// Which `/config` palette slot to paint. Defaults to ``Appearance/system``.
        /// Captured on the first ``AIChat/makeView()`` — mint a new ``AIChat`` to change it.
        let appearance: Appearance

#if os(macOS)
        /// - Parameters:
        ///   - tokenProvider: Supplies a JWT on demand from the host.
        ///   - resetConversation: Ends the conversation and demand fresh-session token from host.
        ///   - deleteData: Ends the session and request that host wipes visitor data.
        ///   - contextProvider: Per-message page/screen context, resolved at send time **and**
        ///     once at `makeView()` bootstrap for start-prompt `url_pattern` matching (literal
        ///     substring) **and** `GET /api/v1/chat/banners?url=` (server schedule + match).
        ///     Include a path or URL (e.g. `"/products"` or
        ///     `"https://shop.example.com/products/123"`) if patterned chips or banners should
        ///     appear; a SKU blurb alone will only match if it contains the dashboard pattern.
        ///     `nil` / empty falls back to global (null-pattern) prompts / all-page + default
        ///     banners. Intended for non-identifying context;
        ///     it is forwarded verbatim to the backend, so the host must not pass PII through
        ///     it and owns the privacy declaration for anything identifying it chooses to send.
        ///   - onOpenLink: Receives tapped in-message links for the host to route. Absent
        ///     → default OS open.
        ///   - onClose: Receives the visitor's close action after an optional rating prompt.
        ///     If livechat CSAT is on screen, Close skips that overlay (no POST) then calls
        ///     this. Absent → no SDK close button.
        ///   - onAddToCart: Receives an add-to-cart tap (main actor). Absent → no cart button
        ///     even when `/config` enables add-to-cart. The button is per-card: only cards
        ///     that carry a sku show it. The SDK does not show "added" feedback.
        ///   - onLivechatSessionChange: Receives livechat status / agent-name changes (main
        ///     actor). Typing and message ticks do not fire. Absent → no-op. Polling still
        ///     parks when the sheet is dismissed or the app backgrounds — last value is for
        ///     host badges / re-present.
        ///   - apiBaseURL: Chatbot API host. Defaults to production.
        ///   - attachments: Attachment sources in the composer. Defaults to ``Attachments/photoLibrary``;
        ///     pass ``Attachments/disabled`` when the chatbot's flow does not handle images.
        ///   - rating: Whether to prompt for a **conversation** rating (`POST /rate`) on close.
        ///     Defaults to ``Rating/enabled``. Does **not** gate livechat CSAT.
        ///   - appearance: Palette slot. Defaults to ``Appearance/system``. `.dark` uses
        ///     `/config`'s `dark_theme` (visually light when that slot is a clone). Mint a
        ///     new ``AIChat`` to change this after the first ``AIChat/makeView()``.
        public init(
            tokenProvider: @escaping @Sendable () async throws -> String,
            resetConversation: @escaping @Sendable () async throws -> String,
            deleteData: @escaping @Sendable () async throws -> Void,
            contextProvider: (@Sendable () async -> String?)? = nil,
            onOpenLink: ((URL) -> Void)? = nil,
            onClose: (() -> Void)? = nil,
            onAddToCart: (@MainActor (ProductSelection) -> Void)? = nil,
            onLivechatSessionChange: (@MainActor (LivechatSessionInfo) -> Void)? = nil,
            apiBaseURL: URL = DivergeAPI.productionBaseURL,
            attachments: Attachments = .photoLibrary,
            rating: Rating = .enabled,
            appearance: Appearance = .system
        ) {
            self.tokenProvider = tokenProvider
            self.resetConversation = resetConversation
            self.deleteData = deleteData
            self.contextProvider = contextProvider
            self.onOpenLink = onOpenLink
            self.onClose = onClose
            self.onAddToCart = onAddToCart
            self.onLivechatSessionChange = onLivechatSessionChange
            self.conversationFlow = .bottomUp
            self.apiBaseURL = apiBaseURL
            self.attachments = attachments
            self.rating = rating
            self.appearance = appearance
        }
#else
        /// - Parameters:
        ///   - tokenProvider: Supplies a JWT on demand from the host.
        ///   - resetConversation: Ends the conversation and demand fresh-session token from host.
        ///   - deleteData: Ends the session and request that host wipes visitor data.
        ///   - contextProvider: Per-message page/screen context, resolved at send time **and**
        ///     once at `makeView()` bootstrap for start-prompt `url_pattern` matching (literal
        ///     substring) **and** `GET /api/v1/chat/banners?url=` (server schedule + match).
        ///     Include a path or URL (e.g. `"/products"` or
        ///     `"https://shop.example.com/products/123"`) if patterned chips or banners should
        ///     appear; a SKU blurb alone will only match if it contains the dashboard pattern.
        ///     `nil` / empty falls back to global (null-pattern) prompts / all-page + default
        ///     banners. Intended for non-identifying context;
        ///     it is forwarded verbatim to the backend, so the host must not pass PII through
        ///     it and owns the privacy declaration for anything identifying it chooses to send.
        ///   - onOpenLink: Receives tapped in-message links for the host to route. Absent
        ///     → default OS open.
        ///   - onClose: Receives the visitor's close action after an optional rating prompt.
        ///     If livechat CSAT is on screen, Close skips that overlay (no POST) then calls
        ///     this. Absent → no SDK close button.
        ///   - onAddToCart: Receives an add-to-cart tap (main actor). Absent → no cart button
        ///     even when `/config` enables add-to-cart. The button is per-card: only cards
        ///     that carry a sku show it. The SDK does not show "added" feedback.
        ///   - onLivechatSessionChange: Receives livechat status / agent-name changes (main
        ///     actor). Typing and message ticks do not fire. Absent → no-op. Polling still
        ///     parks when the sheet is dismissed or the app backgrounds — last value is for
        ///     host badges / re-present.
        ///   - conversationFlow: The layout the conversation flows in. Defaults to ``ConversationFlow/topDown``.
        ///   - apiBaseURL: Chatbot API host. Defaults to production.
        ///   - attachments: Attachment sources in the composer. Defaults to ``Attachments/photoLibrary``;
        ///     pass ``Attachments/disabled`` when the chatbot's flow does not handle images.
        ///   - rating: Whether to prompt for a **conversation** rating (`POST /rate`) on close.
        ///     Defaults to ``Rating/enabled``. Does **not** gate livechat CSAT.
        ///   - appearance: Palette slot. Defaults to ``Appearance/system``. `.dark` uses
        ///     `/config`'s `dark_theme` (visually light when that slot is a clone). Mint a
        ///     new ``AIChat`` to change this after the first ``AIChat/makeView()``.
        public init(
            tokenProvider: @escaping @Sendable () async throws -> String,
            resetConversation: @escaping @Sendable () async throws -> String,
            deleteData: @escaping @Sendable () async throws -> Void,
            contextProvider: (@Sendable () async -> String?)? = nil,
            onOpenLink: ((URL) -> Void)? = nil,
            onClose: (() -> Void)? = nil,
            onAddToCart: (@MainActor (ProductSelection) -> Void)? = nil,
            onLivechatSessionChange: (@MainActor (LivechatSessionInfo) -> Void)? = nil,
            conversationFlow: ConversationFlow = .topDown,
            apiBaseURL: URL = DivergeAPI.productionBaseURL,
            attachments: Attachments = .photoLibrary,
            rating: Rating = .enabled,
            appearance: Appearance = .system
        ) {
            self.tokenProvider = tokenProvider
            self.resetConversation = resetConversation
            self.deleteData = deleteData
            self.contextProvider = contextProvider
            self.onOpenLink = onOpenLink
            self.onClose = onClose
            self.onAddToCart = onAddToCart
            self.onLivechatSessionChange = onLivechatSessionChange
            self.conversationFlow = conversationFlow
            self.apiBaseURL = apiBaseURL
            self.attachments = attachments
            self.rating = rating
            self.appearance = appearance
        }
#endif
    }
}
