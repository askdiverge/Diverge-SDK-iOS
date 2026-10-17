//
//  ChatViewModelAttachmentTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// The composer's photo path: picked bytes → encoder → pending chip → send / restore.
@Suite("ChatView.ViewModel — photo attachments")
@MainActor
struct ChatViewModelAttachmentTests {

    // MARK: - Ingest

    @Test("a picked photo becomes one chip with a generic label and no filename")
    func ingestAppendsChip() async throws {
        let viewModel = try Self.makeViewModel(encoding: .success(Self.encoded(data: "AA==")))

        await viewModel.ingestPickedPhoto(Data([0x01]))

        #expect(viewModel.pendingAttachments.count == 1)
        let pending = try #require(viewModel.pendingAttachments.first)
        #expect(pending.displayName == L10n.mediaImageLabel.string)
        #expect(pending.attachment.filename == nil, "the picker's asset id must never become a filename")
        #expect(pending.attachment.kind == .image)
        #expect(pending.attachment.dataBase64 == "AA==")
        #expect(viewModel.isEncodingAttachment == false)
        #expect(viewModel.notice == nil)
    }

    @Test("isEncodingAttachment is true while the encoder runs")
    func encodingFlagWhileBusy() async throws {
        let gate = Gate()
        let encoded = try Self.encoded(data: "AA==")
        let viewModel = Self.makeViewModel { _, _ throws(ImageAttachment.Failure) in
            gate.wait()
            return encoded
        }

        let ingest = Task { await viewModel.ingestPickedPhoto(Data([0x01])) }
        try await Task.sleep(for: .milliseconds(50))
        let during = viewModel.isEncodingAttachment
        gate.open()
        await ingest.value

        #expect(during == true)
        #expect(viewModel.isEncodingAttachment == false)
    }

    @Test("a photo that cannot be decoded surfaces the failure notice and adds no chip")
    func decodingFailedSurfacesNotice() async {
        let viewModel = Self.makeViewModel(encoding: .failure(.decodingFailed))

        await viewModel.ingestPickedPhoto(Data([0x01]))

        #expect(viewModel.pendingAttachments.isEmpty)
        #expect(viewModel.notice?.message == L10n.attachmentFailed.string)
        #expect(viewModel.isEncodingAttachment == false)
    }

    @Test("a photo still over the cap after downsampling surfaces the too-large notice")
    func tooLargeSurfacesNotice() async {
        let viewModel = Self.makeViewModel(encoding: .failure(.tooLarge))

        await viewModel.ingestPickedPhoto(Data([0x01]))

        #expect(viewModel.pendingAttachments.isEmpty)
        #expect(viewModel.notice?.message == L10n.attachmentTooLarge.string)
    }

    @Test("presentAttachmentFailure shows the same notice the ingest failure path does")
    func loadFailureNotice() {
        let viewModel = Self.makeViewModel(encoding: .failure(.decodingFailed))

        viewModel.presentAttachmentFailure()

        #expect(viewModel.notice?.message == L10n.attachmentFailed.string)
        #expect(viewModel.notice?.edge == .bottom)
    }

    // MARK: - Cap

    @Test("a second pick appends — both photos ride along with the next send")
    func secondPickAppends() async throws {
        #expect(ChatView.ViewModel.maxPendingAttachments == 8)
        let results = Queue([try Self.encoded(data: "AA=="), try Self.encoded(data: "BB==")])
        let viewModel = Self.makeViewModel { _, _ throws(ImageAttachment.Failure) in results.next() }

        await viewModel.ingestPickedPhoto(Data([0x01]))
        await viewModel.ingestPickedPhoto(Data([0x02]))

        #expect(viewModel.pendingAttachments.map(\.attachment.dataBase64) == ["AA==", "BB=="])
    }

    @Test("a ninth pick drops the oldest chip")
    func ninthPickDropsOldest() async throws {
        let payloads = ["AA==", "BB==", "CC==", "DD==", "EE==", "FF==", "GG==", "HH==", "II=="]
        let results = Queue(try payloads.map { try Self.encoded(data: $0) })
        let viewModel = Self.makeViewModel { _, _ throws(ImageAttachment.Failure) in results.next() }

        for _ in 0..<9 {
            await viewModel.ingestPickedPhoto(Data([0x01]))
        }

        #expect(viewModel.pendingAttachments.map(\.attachment.dataBase64) == Array(payloads.dropFirst()))
    }

    // MARK: - Send and restore

    @Test("a photo sent while a reset / delete is in flight comes back to the composer")
    func busyOperationRestoresDraftAndPhoto() async throws {
        let provider = StubChatProviding(sendFailure: .busy(.operation))
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        let pending = Self.pending(data: "AA==")
        viewModel.pendingAttachments = [pending]
        viewModel.currentMessage = "look at this"

        try await viewModel.send()

        #expect(viewModel.currentMessage == "look at this")
        #expect(viewModel.pendingAttachments == [pending])
        #expect(provider.lastAttachments == [pending.attachment])
        #expect(viewModel.notice == nil, "the operation's own UI covers the wait; no extra banner")
    }

    @Test("a chip picked while the send is in flight is not overwritten by the bounce")
    func midFlightPickSurvivesBounce() async throws {
        let provider = StubChatProviding(sendFailure: .busy(.streaming))
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        let bounced = Self.pending(data: "AA==")
        let picked = Self.pending(data: "BB==")
        viewModel.pendingAttachments = [bounced]
        provider.onSend = { viewModel.pendingAttachments.append(picked) }

        try await viewModel.send()

        // Bounced chips are put back *in front of* the mid-flight pick; the cap then keeps the
        // newest eight, so both the bounce and the pick the user just made survive.
        #expect(viewModel.pendingAttachments == [bounced, picked])
    }

    @Test("a successful send clears the chips and the draft")
    func successClearsComposer() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.pendingAttachments = [Self.pending(data: "AA==")]
        viewModel.currentMessage = "caption"

        try await viewModel.send()

        #expect(viewModel.pendingAttachments.isEmpty)
        #expect(viewModel.currentMessage.isEmpty)
        #expect(provider.lastSent == "caption")
        #expect(provider.lastAttachments.map(\.dataBase64) == ["AA=="])
    }

    @Test("a whitespace-only draft sent with a photo sends no text part")
    func whitespaceDraftSendsNoText() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.pendingAttachments = [Self.pending(data: "AA==")]
        viewModel.currentMessage = "   "

        try await viewModel.send()

        #expect(provider.lastSent == "")
        #expect(provider.lastAttachments.map(\.dataBase64) == ["AA=="])
    }

    @Test("an agent session that refuses photos gets none: the chips go with a notice and the text stays")
    func agentRefusingPhotos() async throws {
        let provider = StubChatProviding()
        let service = MockChatService()
        service.livechatState = LivechatState(status: .active)
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            // Ends the poll loop at its first wait, so only the reads a test triggers run.
            livechat: LivechatSession(service: service) { _ in throw CancellationError() }
        )
        viewModel.startLivechat(with: try LivechatFixtures.decoder.decode(LivechatConfig.self, from: Data(
            #"{"enabled":true,"configured":true,"availability_status":"live","attachments_enabled":false}"#.utf8
        )))
        try await eventually { viewModel.livechatStatus == .active }
        viewModel.pendingAttachments = [Self.pending(data: "AA==")]
        viewModel.currentMessage = "here"

        try await viewModel.send()

        #expect(!viewModel.canAttachConsideringLivechat)
        #expect(provider.lastLivechatSent == nil)
        #expect(viewModel.pendingAttachments.isEmpty)
        #expect(viewModel.currentMessage == "here")
        #expect(viewModel.notice?.message == L10n.livechatAttachmentsDropped.string)
    }

    @Test("the controls wait while a pick loads, and until every overlapping encode is done")
    func preparingCoversLoadAndOverlap() async throws {
        let viewModel = try Self.makeViewModel(encoding: .success(Self.encoded(data: "AA==")))

        await viewModel.preparingAttachment {
            #expect(viewModel.isEncodingAttachment)
            await viewModel.ingestPickedPhoto(Data([0x01]))
            #expect(viewModel.isEncodingAttachment, "the pick's own encode finishing doesn't end the pick")
        }

        #expect(!viewModel.isEncodingAttachment)
        #expect(viewModel.pendingAttachments.count == 1)
    }

    @Test("the host flag reaches the view model")
    func attachmentsFlag() {
        let disabled = ChatView.ViewModel.forTesting(provider: StubChatProviding(), attachments: .disabled)
        let enabled = ChatView.ViewModel.forTesting(provider: StubChatProviding())

        #expect(disabled.attachments == .disabled)
        #expect(enabled.attachments == .photoLibrary)
    }

    // MARK: - Shared attach rule

    // `canAttach` is the one enable rule both entry points read (composer attach button and the
    // upload-prompt card), so pinning it here pins both.

    @Test("canAttach is true when attachments are offered and nothing is in flight")
    func canAttachIdle() {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())

        #expect(viewModel.offersAttachments)
        #expect(!viewModel.isStreaming)
        #expect(viewModel.canAttach)
    }

    @Test("canAttach is false when the host disabled attachments")
    func canAttachHostDisabled() {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding(), attachments: .disabled)

        #expect(!viewModel.offersAttachments)
        #expect(!viewModel.canAttach)
    }

    @Test("canAttach is false while a photo is encoding")
    func canAttachWhileEncoding() async throws {
        let gate = Gate()
        let encoded = try Self.encoded(data: "AA==")
        let viewModel = Self.makeViewModel { _, _ throws(ImageAttachment.Failure) in
            gate.wait()
            return encoded
        }

        let ingest = Task { await viewModel.ingestPickedPhoto(Data([0x01])) }
        try await eventually { viewModel.isEncodingAttachment }
        let during = viewModel.canAttach
        gate.open()
        await ingest.value

        #expect(during == false)
        #expect(viewModel.canAttach)
    }

    @Test("canAttach is false while a reply streams and true again once it settles")
    func canAttachWhileStreaming() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)

        provider.publish(ConversationSnapshot(user: [], incoming: [], isUserInitiatedConversation: false, streamingTurnID: UUID()))
        try await eventually { viewModel.isStreaming }
        #expect(!viewModel.canAttach)

        provider.publish(ConversationSnapshot(user: [], incoming: [], isUserInitiatedConversation: false, streamingTurnID: nil))
        try await eventually { !viewModel.isStreaming }
        #expect(viewModel.canAttach)
    }

    @Test("ingest lands a filename-less chip")
    func ingestLandsFilenamelessChip() async throws {
        // Both entry points (composer button, upload-prompt card) funnel into ChatView.ingest →
        // ingestPickedPhoto; there is no separate prompt-path encoder.
        let viewModel = try Self.makeViewModel(encoding: .success(Self.encoded(data: "AA==")))

        await viewModel.ingestPickedPhoto(Data([0x01]))

        #expect(viewModel.pendingAttachments.count == 1)
        #expect(viewModel.pendingAttachments.first?.attachment.dataBase64 == "AA==")
        #expect(viewModel.pendingAttachments.first?.attachment.filename == nil)
    }

    // MARK: - Fixtures

    private static func makeViewModel(
        encoding result: Result<ImageAttachment.Encoded, ImageAttachment.Failure>
    ) -> ChatView.ViewModel {
        Self.makeViewModel { _, _ throws(ImageAttachment.Failure) in try result.get() }
    }

    private static func makeViewModel(
        encoder: @escaping ChatView.ViewModel.AttachmentEncoder
    ) -> ChatView.ViewModel {
        .forTesting(provider: StubChatProviding(), encodeAttachment: encoder)
    }

    private static func encoded(data: String) throws -> ImageAttachment.Encoded {
        ImageAttachment.Encoded(
            attachment: OutgoingAttachment(kind: .image, data: data, mime: "image/jpeg", filename: nil)!,
            thumbnail: try ImageFixtures.image(width: 2, height: 2)
        )
    }

    private static func pending(data: String) -> PendingAttachment {
        PendingAttachment(
            thumbnail: Image(systemName: "photo"),
            attachment: OutgoingAttachment(kind: .image, data: data, mime: "image/jpeg", filename: nil)!,
            displayName: L10n.mediaImageLabel.string
        )
    }
}

/// A one-shot latch the encoder stub blocks on so a test can observe the in-flight state.
private final class Gate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { self.semaphore.wait() }
    func open() { self.semaphore.signal() }
}

/// Scripted encoder results, handed out in order.
private final class Queue<Element>: @unchecked Sendable {
    private var items: [Element]
    private let lock = NSLock()
    init(_ items: [Element]) { self.items = items }
    func next() -> Element { self.lock.withLock { self.items.removeFirst() } }
}
