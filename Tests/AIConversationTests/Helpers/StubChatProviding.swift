//
//  StubChatProviding.swift
//  AIConversationTests
//

import Foundation
@testable import AIConversation
@testable import AIConversationEngine

/// Minimal ``ChatProviding`` stub for view-model tests: records the last send, optionally fails
/// it with a scripted ``ChatProvider/SendFailure``, runs `onSend` while the send is in flight so
/// a test can interleave view-model mutations with it, and lets a test `publish` a snapshot to
/// drive the view model's snapshot-derived state (e.g. `isStreaming`).
final class StubChatProviding: ChatProviding, @unchecked Sendable {

    private let sendFailure: ChatProvider.SendFailure?
    private let continuation: AsyncStream<ConversationSnapshot>.Continuation
    private(set) var lastSent: String?
    private(set) var lastAttachments: [OutgoingAttachment]?
    /// Runs on the main actor after the send is recorded and before it completes or throws.
    var onSend: (@MainActor () -> Void)?

    init(sendFailure: ChatProvider.SendFailure? = nil) {
        self.sendFailure = sendFailure
        (self.stream, self.continuation) = AsyncStream<ConversationSnapshot>.makeStream()
    }

    deinit {
        self.continuation.finish()
    }

    nonisolated let stream: AsyncStream<ConversationSnapshot>

    /// Pushes a snapshot to whoever observes `stream` — the view model, once attached.
    func publish(_ snapshot: ConversationSnapshot) {
        self.continuation.yield(snapshot)
    }

    func send(_ text: String, attachments: [OutgoingAttachment]) async throws(ChatProvider.SendFailure) {
        self.lastSent = text
        self.lastAttachments = attachments
        if let onSend {
            await onSend()
        }
        if let sendFailure {
            throw sendFailure
        }
    }

    func loadOlder() async throws -> Bool { false }
    var resetError: Error?
    func reset() async throws {
        if let resetError { throw resetError }
    }
    func delete() async throws {}

    private(set) var exportCallCount = 0
    var exportData: Data = Data(#"{"ok":true}"#.utf8)
    var exportError: ChatServiceError?

    func exportMyData() async throws(ChatServiceError) -> Data {
        self.exportCallCount += 1
        if let exportError { throw exportError }
        return self.exportData
    }
}

extension ChatView.ViewModel {

    /// A view model over a throwaway `ChatService` with `provider` attached.
    @MainActor
    static func forTesting(
        provider: StubChatProviding,
        attachments: AIChat.Attachments = .photoLibrary,
        appearancePreference: AIChat.Appearance = .system,
        onClose: (() -> Void)? = {},
        onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)? = nil,
        encodeAttachment: AttachmentEncoder? = nil
    ) -> ChatView.ViewModel {
        let service = ChatService(
            tokenProvider: { "token" },
            onResetConversation: { "token" },
            onDeleteData: {}
        )
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: nil,
            conversationFlow: .topDown,
            attachments: attachments,
            appearancePreference: appearancePreference,
            onClose: onClose,
            onAddToCart: onAddToCart,
            encodeAttachment: encodeAttachment
        )
        viewModel.attachProviderForTesting(provider)
        return viewModel
    }
}
