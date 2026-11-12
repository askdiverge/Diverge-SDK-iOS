//
//  ChatProviderPhotoUploadTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Attachment sends and image parts as `ChatProvider` folds them, over `MockChatService`; no
/// server is involved.
@Suite("ChatProvider — photo upload wire")
struct ChatProviderPhotoUploadTests {

    @Test("image and upload-marker parts join the incoming pane when the host accepts prompts")
    func imagePartsJoinPanes() async throws {
        let image = try Self.imagePart()
        let marker = try Self.uploadMarkerPart()
        let history = Message(
            messageId: "m_img",
            role: .assistant,
            agent: nil,
            parts: [Self.textPart("look"), image, marker],
            createdAt: "2026-01-01T00:00:00Z"
        )
        let mock = MockChatService(.init(historyPages: [MessagePage(messages: [history], nextCursor: nil)]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        try await provider.loadOlder()

        var snapshots = provider.stream.makeAsyncIterator()
        let snapshot = await snapshots.next()
        guard case .image(let decoded) = image else {
            Issue.record("fixture must be an image part")
            return
        }
        guard case .requestImageUpload(let upload) = marker else {
            Issue.record("fixture must be an upload marker")
            return
        }
        #expect(snapshot?.incoming.map(\.model) == [[
            .text(AttributedString("look")),
            .image(decoded),
            .requestImageUpload(upload)
        ]])
    }

    @Test("upload markers are omitted when the host disabled attachments")
    func uploadMarkersGatedOff() async throws {
        let history = Message(
            messageId: "m_img",
            role: .assistant,
            agent: nil,
            parts: [Self.textPart("look"), try Self.uploadMarkerPart()],
            createdAt: "2026-01-01T00:00:00Z"
        )
        let mock = MockChatService(.init(historyPages: [MessagePage(messages: [history], nextCursor: nil)]))
        let provider: any ChatProviding = ChatProvider(
            service: mock,
            pageContext: { nil },
            acceptsImageUploadPrompts: false
        )
        try await provider.loadOlder()

        var snapshots = provider.stream.makeAsyncIterator()
        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("look"))]])
    }

    @Test("history user image parts become UserContent.image")
    func historyUserImage() async throws {
        let image = try Self.imagePart()
        let history = Message(
            messageId: "m_user",
            role: .user,
            agent: nil,
            parts: [Self.textPart("see"), image],
            createdAt: "2026-01-01T00:00:00Z"
        )
        let mock = MockChatService(.init(historyPages: [MessagePage(messages: [history], nextCursor: nil)]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        try await provider.loadOlder()

        var snapshots = provider.stream.makeAsyncIterator()
        let snapshot = await snapshots.next()
        guard case .image(let decoded) = image else {
            Issue.record("fixture must be an image part")
            return
        }
        #expect(snapshot?.user.map(\.model) == [[
            .text(AttributedString("see")),
            .image(decoded)
        ]])
    }

    @Test("send with an attachment echoes it after the text and posts it")
    func sendEchoesAttachment() async throws {
        let mock = MockChatService(.init(sendEvents: []))
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let provider: any ChatProviding = sut
        var snapshots = provider.stream.makeAsyncIterator()
        let image = try Self.image()

        try await sut.send("see", attachments: [image])

        // First publish is the optimistic echo (before the stream settles).
        let echo = await snapshots.next()
        #expect(echo?.user.first?.model == [.text(AttributedString("see")), .attachment(image)])
        #expect(mock.sentAttachments == [[image]])
    }

    @Test("a send with neither text nor attachments posts nothing")
    func emptySendPostsNothing() async throws {
        let mock = MockChatService()
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)

        try await sut.send("", attachments: [])
        try await sut.sendLivechat("", attachments: [])

        #expect(mock.sentAttachments.isEmpty)
    }

    @Test("a failed attachment send pops its whole echo, keeps the earlier unanswered bubble, and hands the attachments back")
    func failedSendPopsEcho() async throws {
        let mock = MockChatService(.init(sendError: .transport(.http(.unhandled(status: 500, body: Data())))))
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let provider: any ChatProviding = sut
        await provider.appendLivechat([
            LivechatFixtures.message("u1", role: .user, text: "one", sequence: 1),
            LivechatFixtures.message("a1", role: .agent, text: "answer", sequence: 2),
            LivechatFixtures.message("u2", role: .user, text: "two", sequence: 3)
        ])
        var snapshots = provider.stream.makeAsyncIterator()
        let image = try Self.image()

        await #expect(throws: ChatProvider.SendFailure.retry(popped: .init(text: "three", attachments: [image]), body: nil)) {
            try await sut.send("three", attachments: [image])
        }

        #expect(await snapshots.next()?.user.map(\.model) == [[.text(AttributedString("one"))], [.text(AttributedString("two"))]])
    }

    @Test("a 409 on an attachment-only send hands the attachments back for the agent")
    func conflictHandsAttachmentsBack() async throws {
        let mock = MockChatService(.init(sendError: .conflict))
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let image = try Self.image()

        await #expect(throws: ChatProvider.SendFailure.livechatActive(popped: .init(text: "", attachments: [image]))) {
            try await sut.send("", attachments: [image])
        }
    }

    @Test("a livechat attachment send posts the attachments and keeps the echo")
    func livechatSendPostsAttachments() async throws {
        let mock = MockChatService()
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let provider: any ChatProviding = sut
        var snapshots = provider.stream.makeAsyncIterator()
        let image = try Self.image()

        try await sut.sendLivechat("see", attachments: [image])

        #expect(mock.sentAttachments == [[image]])
        #expect(await snapshots.next()?.user.map(\.model) == [[.text(AttributedString("see")), .attachment(image)]])
    }

    @Test("a failed livechat attachment send pops only its own bubbles")
    func failedLivechatSendPopsOwnBubbles() async throws {
        let mock = MockChatService(.init(sendEvents: [Self.textEvent("reply")], livechatSendError: .conflict))
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let provider: any ChatProviding = sut
        try await provider.send("hi")
        await provider.appendLivechat([LivechatFixtures.message("u1", role: .user, text: "one")])
        var snapshots = provider.stream.makeAsyncIterator()
        let image = try Self.image()

        await #expect(throws: ChatProvider.SendFailure.livechatInactive(popped: .init(text: "two", attachments: [image]))) {
            try await sut.sendLivechat("two", attachments: [image])
        }

        #expect(await snapshots.next()?.user.map(\.model) == [[.text(AttributedString("hi"))], [.text(AttributedString("one"))]])
    }

    @Test("a timed-out attachment send is posted again with its attachments under the same operation id")
    func timedOutAttachmentSendIsRetried() async throws {
        let mock = MockChatService(.init(livechatSendFailingCalls: [0: .transport(.connection(URLError(.timedOut)))]))
        let sut = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let image = try Self.image()

        try await sut.sendLivechat("hi", attachments: [image])

        #expect(mock.sentAttachments == [[image], [image]])
        #expect(mock.livechatSendOperationIds.count == 2)
        #expect(Set(mock.livechatSendOperationIds).count == 1)
    }
}

private extension ChatProviderPhotoUploadTests {

    static func image() throws -> OutgoingAttachment {
        try #require(OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: nil))
    }

    static func textPart(_ text: String) -> Part {
        .richText(RichText(partId: "p_\(text)", blocks: [.paragraph(.init(spans: [.text(text)]))]))
    }

    static func textEvent(_ text: String) -> StreamEvent {
        .part(Self.textPart(text))
    }

    static func imagePart() throws -> Part {
        try LivechatFixtures.decoder.decode(Part.self, from: Data(#"""
        { "type": "image", "url": "https://cdn.example/a.jpg", "caption": "shot" }
        """#.utf8))
    }

    static func uploadMarkerPart() throws -> Part {
        try LivechatFixtures.decoder.decode(Part.self, from: Data(#"""
        {
          "type": "request_image_upload",
          "part_id": "upload_1",
          "accepted_types": ["image/png"],
          "max_size_bytes": 5242880
        }
        """#.utf8))
    }
}
