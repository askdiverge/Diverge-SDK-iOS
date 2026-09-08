//
//  ChatViewModelExportTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — GDPR export", .serialized)
struct ChatViewModelExportTests {

    @Test("export writes a JSON file and leaves rating / conversation state alone")
    @MainActor
    func exportWritesTempFile() async throws {
        let session = RatingSession()
        let provider = StubChatProviding()
        provider.exportData = Data(
            #"{"generated_at":"2026-01-01T00:00:00Z","chatbot_id":"bot","visitor_id":"v"}"#.utf8
        )
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in }
        )
        _ = viewModel.beginRating()
        try await viewModel.submitRating(score: 5, feedback: nil)
        #expect(session.hasRated == true)

        let url = try await viewModel.exportMyData()

        #expect(provider.exportCallCount == 1)
        #expect(url.lastPathComponent == "diverge-export.json")
        #expect(url == ChatView.ViewModel.exportFileURL)
        let data = try Data(contentsOf: url)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["visitor_id"] as? String == "v")
        #expect(session.hasRated == true)
        #expect(viewModel.ratingSessionHasRated == true)
        viewModel.discardExportFile()
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("export 401 maps to SessionEnded")
    @MainActor
    func export401IsSessionEnded() async {
        let provider = StubChatProviding()
        provider.exportError = .sessionExpired
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)

        do {
            _ = try await viewModel.exportMyData()
            Issue.record("expected SessionEnded")
        } catch is ChatView.SessionEnded {
            #expect(provider.exportCallCount == 1)
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
    }

    @Test("non-JSON export body fails as ExportFailed")
    @MainActor
    func invalidJSONFails() async {
        let provider = StubChatProviding()
        provider.exportData = Data("not-json".utf8)
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)

        do {
            _ = try await viewModel.exportMyData()
            Issue.record("expected ExportFailed")
        } catch is ChatView.ExportFailed {
            // expected
        } catch {
            Issue.record("expected ExportFailed, got \(error)")
        }
    }

    @Test("transport failure maps to ExportFailed")
    @MainActor
    func transportFailsAsExportFailed() async {
        let provider = StubChatProviding()
        provider.exportError = .transport(.http(.unhandled(status: 500)))
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)

        do {
            _ = try await viewModel.exportMyData()
            Issue.record("expected ExportFailed")
        } catch is ChatView.ExportFailed {
            // expected
        } catch {
            Issue.record("expected ExportFailed, got \(error)")
        }
    }

    @Test("a JSON array body is rejected as ExportFailed")
    @MainActor
    func jsonArrayFails() async {
        let provider = StubChatProviding()
        provider.exportData = Data("[]".utf8)
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.discardExportFile()

        do {
            _ = try await viewModel.exportMyData()
            Issue.record("expected ExportFailed")
        } catch is ChatView.ExportFailed {
            #expect(FileManager.default.fileExists(atPath: ChatView.ViewModel.exportFileURL.path) == false)
        } catch {
            Issue.record("expected ExportFailed, got \(error)")
        }
    }

    @Test("a second export overwrites the same temp file")
    @MainActor
    func exportReusesStablePath() async throws {
        let provider = StubChatProviding()
        provider.exportData = Data(#"{"visitor_id":"one"}"#.utf8)
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        let first = try await viewModel.exportMyData()
        provider.exportData = Data(#"{"visitor_id":"two"}"#.utf8)
        let second = try await viewModel.exportMyData()
        #expect(first == second)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: second)) as? [String: Any]
        )
        #expect(object["visitor_id"] as? String == "two")
        viewModel.discardExportFile()
    }
}
