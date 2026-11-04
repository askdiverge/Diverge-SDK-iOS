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
    func rejectsUnsupportedTypes() async throws {
        let marker = try Self.marker(acceptedTypes: ["image/png"], maxSizeBytes: 1_000_000)
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        await viewModel.ingestPromptPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]), marker: marker)
        #expect(viewModel.pendingAttachments.isEmpty)
    }

    @Test("ingestPromptPhoto honours the marker byte cap")
    func honoursMaxSize() async throws {
        let data = try ImageFixtures.png(width: 2000, height: 2000)
        let marker = try Self.marker(acceptedTypes: ["image/jpeg", "image/png"], maxSizeBytes: 4_000)
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        await viewModel.ingestPromptPhoto(data, marker: marker)
        #expect(viewModel.pendingAttachments.isEmpty)
    }

    @Test("ingestPromptPhoto accepts jpeg markers within budget")
    func acceptsWithinBudget() async throws {
        let data = try ImageFixtures.png(width: 200, height: 200)
        let marker = try Self.marker(acceptedTypes: ["image/png", "image/jpeg", "image/webp"], maxSizeBytes: 5_242_880)
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        await viewModel.ingestPromptPhoto(data, marker: marker)
        #expect(viewModel.pendingAttachments.count == 1)
    }

    /// A marker decoded the way the wire sends it.
    private static func marker(acceptedTypes: [String], maxSizeBytes: Int) throws -> RequestImageUpload {
        let json = try JSONSerialization.data(withJSONObject: [
            "part_id": "upload",
            "accepted_types": acceptedTypes,
            "max_size_bytes": maxSizeBytes
        ])
        return try LivechatFixtures.decoder.decode(RequestImageUpload.self, from: json)
    }
}
