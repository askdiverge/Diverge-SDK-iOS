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
            onDeleteData: configuration.deleteData
        )
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

    /// The chat UI as a SwiftUI view. The session is tied to this instance
    /// presentation (sheet, cover, push) is the caller's responsibility.
    func makeView() -> some View {
        ChatView(
            viewModel: .init(
                service: self.service,
                contextProvider: self.configuration.contextProvider,
                conversationFlow: self.configuration.conversationFlow
            )
        )
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

    /// The host-provided hooks the SDK is configured with. This is the single injection
    /// surface,  both ``AIChat/configure(_:)`` and ``AIChat/init(_:)`` take it.
    ///
    /// The three hooks (`tokenProvider`, `resetConversation`, `deleteData`) are required —
    /// the SDK is not correctly configured without them (Control Plane: Identity, Minting, Invalidation).
    /// SDK is pure (Data plane) to avoid split Token Ownership, Distributed State with Async Reconciliation and Structural Inversion.
    ///
    /// The two enhancement hooks (`contextProvider`, `onOpenLink`) are optional and degrade gracefully when omitted.
    struct Configuration {

        let tokenProvider: @Sendable () async throws -> String
        let resetConversation: @Sendable () async throws -> String
        let deleteData: @Sendable () async throws -> Void
        let contextProvider: (@Sendable () async -> String?)?
        let onOpenLink: ((URL) -> Void)?
        let conversationFlow: ConversationFlow

#if os(macOS)
        /// - Parameters:
        ///   - tokenProvider: Supplies a JWT on demand from the host.
        ///   - resetConversation: Ends the conversation and demand fresh-session token from host.
        ///   - deleteData: Ends the session and request that host wipes visitor data.
        ///   - contextProvider: Per-message page/screen context, resolved at send time.
        ///     `nil` → no context sent. Intended for non-identifying context (SKU, category, screen
        ///     name); it is forwarded verbatim to the backend, so the host must not pass PII through
        ///     it and owns the privacy declaration for anything identifying it chooses to send.
        ///   - onOpenLink: Receives tapped in-message links for the host to route. Absent
        ///     → default OS open.
        public init(
            tokenProvider: @escaping @Sendable () async throws -> String,
            resetConversation: @escaping @Sendable () async throws -> String,
            deleteData: @escaping @Sendable () async throws -> Void,
            contextProvider: (@Sendable () async -> String?)? = nil,
            onOpenLink: ((URL) -> Void)? = nil
        ) {
            self.tokenProvider = tokenProvider
            self.resetConversation = resetConversation
            self.deleteData = deleteData
            self.contextProvider = contextProvider
            self.onOpenLink = onOpenLink
            self.conversationFlow = .bottomUp
        }
#else
        /// - Parameters:
        ///   - tokenProvider: Supplies a JWT on demand from the host.
        ///   - resetConversation: Ends the conversation and demand fresh-session token from host.
        ///   - deleteData: Ends the session and request that host wipes visitor data.
        ///   - contextProvider: Per-message page/screen context, resolved at send time.
        ///     `nil` → no context sent. Intended for non-identifying context (SKU, category, screen
        ///     name); it is forwarded verbatim to the backend, so the host must not pass PII through
        ///     it and owns the privacy declaration for anything identifying it chooses to send.
        ///   - onOpenLink: Receives tapped in-message links for the host to route. Absent
        ///     → default OS open.
        ///   - conversationFlow: The layout the conversation flows in. Defaults to ``ConversationFlow/topDown``.
        public init(
            tokenProvider: @escaping @Sendable () async throws -> String,
            resetConversation: @escaping @Sendable () async throws -> String,
            deleteData: @escaping @Sendable () async throws -> Void,
            contextProvider: (@Sendable () async -> String?)? = nil,
            onOpenLink: ((URL) -> Void)? = nil,
            conversationFlow: ConversationFlow = .topDown
        ) {
            self.tokenProvider = tokenProvider
            self.resetConversation = resetConversation
            self.deleteData = deleteData
            self.contextProvider = contextProvider
            self.onOpenLink = onOpenLink
            self.conversationFlow = conversationFlow
        }
#endif
    }
}
