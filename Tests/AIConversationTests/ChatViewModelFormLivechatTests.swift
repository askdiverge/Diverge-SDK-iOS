//
//  ChatViewModelFormLivechatTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — form start_livechat", .serialized)
@MainActor
struct ChatViewModelFormLivechatTests {

    private let startLivechatForm = ConversationForm.custom(ShowForm(
        partId: "part_start_lc",
        formId: "startLivechatLead",
        name: "Request a person",
        confirmationText: "Connecting…",
        fields: [
            .init(key: "email", label: "Email", type: .email, required: true)
        ],
        minFilledFields: 1
    ))

    private let contact = ConversationForm.contact(ShowContactForm(
        partId: "part_contact_1",
        fields: [
            .init(key: "name", label: "Name", type: .text, required: true),
            .init(key: "email", label: "Email", type: .email, required: true),
            .init(key: "message", label: "Message", type: .textarea, required: true)
        ]
    ))

    private static let waitingStateBody = Data(#"""
    {
      "status": "waiting",
      "active_agent": null,
      "is_agent_typing": false,
      "agent_joined_at": null,
      "closed_by": null,
      "feedback": { "status": "not_available", "submitted_at": null }
    }
    """#.utf8)

    private static let emptyMessagesBody = Data(#"""
    {"messages":[],"has_more":false}
    """#.utf8)

    /// In-memory store — the default `SubmittedFormStore()` writes Application Support and would
    /// collapse `part_start_lc` on the next run so `submitForm` never adopts the poller.
    private func makeViewModel(
        service: ChatService,
        submitAction: ChatView.ViewModel.ActionSubmitter?
    ) -> ChatView.ViewModel {
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: nil,
            conversationFlow: .topDown,
            submitAction: submitAction,
            submittedForms: SubmittedFormStore(fileURL: nil)
        )
        viewModel.attachProviderForTesting(StubChatProviding())
        return viewModel
    }

    @Test("submitForm with waiting livechat_session bootstraps the poller and never POSTs handover")
    func submitStartsPollerWithoutHandover() async throws {
        var responses: [ScriptedURLProtocol.Response] = [
            .init(status: 200, body: Self.waitingStateBody),
            .init(status: 200, body: Self.emptyMessagesBody)
        ]
        // Poll loop may tick after the 2 s cadence — keep answering waiting.
        for _ in 0..<6 {
            responses.append(.init(status: 200, body: Self.waitingStateBody))
            responses.append(.init(status: 200, body: Self.emptyMessagesBody))
        }
        let (service, script) = ChatServiceFixtures.makeSUT(responses: responses)
        let viewModel = self.makeViewModel(
            service: service,
            submitAction: { _ in
                SubmitActionResponse(
                    submissionId: "sub_lc",
                    confirmationText: "Connecting…",
                    livechatSession: LivechatSessionHint(status: .waiting)
                )
            }
        )

        let model = viewModel.formModel(for: self.startLivechatForm)
        model.setValue("shopper@example.com", for: "email")
        try await viewModel.submitForm(partId: self.startLivechatForm.partId)

        #expect(model.isSubmitted)
        #expect(viewModel.livechatSession != nil, "adopt should attach a LivechatSession")
        var sawWaiting = false
        for _ in 0..<40 {
            if viewModel.livechatStatus == .waiting {
                sawWaiting = true
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(sawWaiting, "bootstrap should move the mirror to waiting")

        let paths = script.requests.compactMap { $0.url?.path() }
        #expect(paths.contains("/api/v1/chat/livechat/state"))
        #expect(!paths.contains { $0.contains("handover") }, "form start_livechat must not POST handover")

        await viewModel.teardownLivechat()
    }

    @Test("contact form without livechat_session does not start the poller")
    func contactWithoutSessionSkipsPoller() async throws {
        let (service, script) = ChatServiceFixtures.makeSUT(responses: [])
        let viewModel = self.makeViewModel(
            service: service,
            submitAction: { _ in
                SubmitActionResponse(submissionId: "sub_1", confirmationText: "Thanks")
            }
        )

        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")
        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(model.isSubmitted)
        #expect(viewModel.livechatStatus == .inactive)
        #expect(viewModel.livechatSession == nil)
        #expect(script.requests.isEmpty, "no livechat bootstrap without livechat_session")
    }

    @Test("submitForm with waiting session still confirms when GET /state fails; no handover")
    func submitBootstrapTransportShowsNotice() async throws {
        let (service, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 500, body: Data())
        ])
        let viewModel = self.makeViewModel(
            service: service,
            submitAction: { _ in
                SubmitActionResponse(
                    submissionId: "sub_lc",
                    confirmationText: "Connecting…",
                    livechatSession: LivechatSessionHint(status: .waiting)
                )
            }
        )

        let model = viewModel.formModel(for: self.startLivechatForm)
        model.setValue("shopper@example.com", for: "email")
        try await viewModel.submitForm(partId: self.startLivechatForm.partId)

        #expect(model.isSubmitted)
        #expect(viewModel.livechatSession != nil, "failed GET /state still attaches the poller")
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
        #expect(viewModel.notice?.edge == .bottom)
        let paths = script.requests.compactMap { $0.url?.path() }
        #expect(!paths.contains { $0.contains("handover") }, "failed bootstrap must not POST handover")
        await viewModel.teardownLivechat()
    }
}
