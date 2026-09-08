//
//  ImageUploadPromptTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("Image upload prompt — marker limits")
@MainActor
struct ImageUploadPromptTests {

    @Test("ingestPromptPhoto rejects markers that omit image/jpeg")
    func rejectsUnsupportedTypes() async {
        let marker = RequestImageUpload(
            partId: "upload",
            acceptedTypes: ["image/png"],
            maxSizeBytes: 1_000_000
        )
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        await viewModel.ingestPromptPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]), marker: marker)
        #expect(viewModel.pendingAttachments.isEmpty)
    }

    @Test("ingestPromptPhoto honours the marker byte cap")
    func honoursMaxSize() async throws {
        let data = try ImageFixtures.png(width: 2000, height: 2000)
        let marker = RequestImageUpload(
            partId: "upload",
            acceptedTypes: ["image/jpeg", "image/png"],
            maxSizeBytes: 4_000
        )
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        await viewModel.ingestPromptPhoto(data, marker: marker)
        #expect(viewModel.pendingAttachments.isEmpty)
    }

    @Test("ingestPromptPhoto accepts jpeg markers within budget")
    func acceptsWithinBudget() async throws {
        let data = try ImageFixtures.png(width: 200, height: 200)
        let marker = RequestImageUpload(
            partId: "upload",
            acceptedTypes: RequestImageUpload.defaultAcceptedTypes,
            maxSizeBytes: RequestImageUpload.defaultMaxSizeBytes
        )
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        await viewModel.ingestPromptPhoto(data, marker: marker)
        #expect(viewModel.pendingAttachments.count == 1)
    }
}
