//
//  StubChatProviding.swift
//  AIConversationTests
//

import Foundation
@testable import AIConversation
@testable import AIConversationEngine

/// Minimal ``ChatProviding`` stub for view-model tests: records the last assistant and agent sends,
/// optionally fails them with a scripted ``ChatProvider/SendFailure``, and lets a test `publish` a
/// snapshot to drive the view model's snapshot-derived state (e.g. `isFormEditable`). Isolated to
/// the main actor, like the view model and the suites that read its records.
@MainActor
final class StubChatProviding: ChatProviding {

    private let sendFailure: ChatProvider.SendFailure?
    private let livechatSendFailure: ChatProvider.SendFailure?
    private let continuation: AsyncStream<ConversationSnapshot>.Continuation
    private(set) var lastSent: String?
    private(set) var lastAttachments: [OutgoingAttachment] = []
    private(set) var lastLivechatSent: String?
    private(set) var lastLivechatAttachments: [OutgoingAttachment] = []
    private(set) var appendedLivechat: [LivechatMessage] = []
    private(set) var resetCount = 0
    private(set) var expireCount = 0
    var resetError: Error?
    var loadOlderError: Error?
    /// Runs while an agent send is in flight, before it returns.
    var whileSendingLivechat: (@MainActor () async -> Void)?
    /// Runs at the start of an assistant send, before the scripted failure (if any).
    var onSend: (@MainActor () -> Void)?

    init(sendFailure: ChatProvider.SendFailure? = nil, livechatSendFailure: ChatProvider.SendFailure? = nil) {
        self.sendFailure = sendFailure
        self.livechatSendFailure = livechatSendFailure
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
        self.onSend?()
        if let sendFailure {
            throw sendFailure
        }
    }

    func loadOlder() async throws {
        if let loadOlderError { throw loadOlderError }
    }

    func reset() async throws {
        self.resetCount += 1
        if let resetError { throw resetError }
    }

    func delete() async throws {}

    func appendLivechat(_ messages: [LivechatMessage]) async {
        self.appendedLivechat += messages
        self.livechatOrder += messages.map { "message:\($0.messageId)" }
    }

    private(set) var notes: [LivechatNote] = []
    /// Livechat messages (`message:<id>`) and notes (`note:<kind>`) in the order they arrived.
    private(set) var livechatOrder: [String] = []

    func note(_ note: LivechatNote) async {
        self.notes.append(note)
        self.livechatOrder.append("note:\(note.kind)")
    }

    func sendLivechat(_ text: String, attachments: [OutgoingAttachment]) async throws(ChatProvider.SendFailure) {
        self.lastLivechatSent = text
        self.lastLivechatAttachments = attachments
        await self.whileSendingLivechat?()
        if let livechatSendFailure {
            throw livechatSendFailure
        }
    }

    func expireSession() async {
        self.expireCount += 1
    }
}

extension ChatView.ViewModel {

    /// A view model over a throwaway `ChatService` with `provider` attached.
    @MainActor
    static func forTesting(
        provider: StubChatProviding,
        attachments: AIChat.Attachments = .photoLibrary,
        onClose: (@MainActor () -> Void)? = {},
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
        livechat: LivechatSession? = nil,
        contextProvider: (@Sendable () async -> String?)? = nil
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
            contextProvider: contextProvider,
            conversationFlow: .topDown,
            attachments: attachments,
            onClose: onClose,
            onLivechatSessionChange: onLivechatSessionChange,
            conversationRatingMode: conversationRatingMode,
            ratingSession: ratingSession,
            encodeAttachment: encodeAttachment,
            submitAction: submitAction,
            fetchForm: fetchForm,
            fetchSession: fetchSession,
            patchFormValues: patchFormValues,
            submitLivechatFeedback: submitLivechatFeedback,
            rateConversation: rateConversation,
            livechat: livechat
        )
        viewModel.attachProviderForTesting(provider)
        return viewModel
    }
}
