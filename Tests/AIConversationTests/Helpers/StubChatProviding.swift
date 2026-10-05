//
//  StubChatProviding.swift
//  AIConversationTests
//

import Foundation
@testable import AIConversation
@testable import AIConversationEngine

/// Minimal ``ChatProviding`` stub for view-model tests: records the last send, optionally fails
/// it with a scripted ``ChatProvider/SendFailure``, and lets a test `publish` a snapshot to
/// drive the view model's snapshot-derived state (e.g. `isFormEditable`).
final class StubChatProviding: ChatProviding, @unchecked Sendable {

    private let sendFailure: ChatProvider.SendFailure?
    private let continuation: AsyncStream<ConversationSnapshot>.Continuation
    private(set) var lastSent: String?
    var resetError: Error?

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

    func send(_ text: String) async throws(ChatProvider.SendFailure) {
        self.lastSent = text
        if let sendFailure {
            throw sendFailure
        }
    }

    func loadOlder() async throws {}

    func reset() async throws {
        if let resetError { throw resetError }
    }

    func delete() async throws {}
}

extension ChatView.ViewModel {

    /// A view model over a throwaway `ChatService` with `provider` attached.
    @MainActor
    static func forTesting(
        provider: StubChatProviding,
        submitAction: ActionSubmitter? = nil,
        fetchForm: FormFetcher? = nil
    ) -> ChatView.ViewModel {
        let service = ChatService(
            tokenProvider: { "token" },
            onResetConversation: { "token" },
            onDeleteData: {},
            sdkVersion: "9.8.7",
            clientProfiles: [.productRecommendation]
        )
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: nil,
            conversationFlow: .topDown,
            submitAction: submitAction,
            fetchForm: fetchForm
        )
        viewModel.attachProviderForTesting(provider)
        return viewModel
    }
}
