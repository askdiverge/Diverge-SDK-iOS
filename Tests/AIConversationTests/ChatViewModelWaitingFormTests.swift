//
//  ChatViewModelWaitingFormTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// The waiting-room form as the chat screen drives it: status from `LivechatSession` snapshots
/// over `MockChatService`, the form and session values from injected fetchers.
@Suite("ChatView.ViewModel — livechat waiting form")
@MainActor
struct ChatViewModelWaitingFormTests {

    @Test("queued, the card loads with the session's values; an agent joining clears it")
    func loadsWhileQueued() async throws {
        let (viewModel, service, _) = try self.makeSUT(
            fetchSession: { try Self.session(#"[{ "key": "email", "value": "shopper@example.com" }]"#) }
        )

        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { viewModel.waitingForm.model != nil }
        #expect(viewModel.waitingForm.model?.values["email"] == "shopper@example.com")

        service.livechatState = LivechatState(status: .active)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.waitingForm.model == nil }
    }

    @Test("saving PATCHes the visible values and keeps the card filled")
    func savePatchesValues() async throws {
        let patches = Recorder<[String: String]>()
        let (viewModel, service, _) = try self.makeSUT(patchFormValues: { _, values in
            patches.record(values)
            return try Self.session(#"[{ "key": "email", "value": "a@b.com" }]"#)
        })
        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { viewModel.waitingForm.model != nil }
        let model = try #require(viewModel.waitingForm.model)

        model.setValue(" a@b.com ", for: "email")
        await viewModel.waitingForm.save()

        #expect(patches.values == [["email": "a@b.com"]])
        #expect(model.isSaved)
        #expect(model.values["email"] == "a@b.com")
    }

    @Test("an emptied field isn't sent, and the card shows the value the server kept")
    func emptiedFieldIsKept() async throws {
        let patches = Recorder<[String: String]>()
        let (viewModel, service, _) = try self.makeSUT(
            fetchSession: {
                try Self.session(#"""
                [{ "key": "email", "value": "a@b.com" }, { "key": "order_number", "value": "42" }]
                """#)
            },
            patchFormValues: { _, values in
                patches.record(values)
                // As the server does: only the keys sent change.
                return try Self.session(#"""
                [{ "key": "email", "value": "c@d.com" }, { "key": "order_number", "value": "42" }]
                """#)
            }
        )
        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { viewModel.waitingForm.model != nil }
        let model = try #require(viewModel.waitingForm.model)

        model.setValue("", for: "order_number")
        #expect(!model.canSave)
        model.setValue("c@d.com", for: "email")
        await viewModel.waitingForm.save()

        #expect(patches.values == [["email": "c@d.com"]])
        #expect(model.values["order_number"] == "42")
    }

    @Test("a 401 on save ends the chat, as the poller's 401 does")
    func expiredSaveEndsChat() async throws {
        let (viewModel, service, provider) = try self.makeSUT(patchFormValues: { _, _ in
            throw ChatServiceError.sessionExpired
        })
        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { viewModel.waitingForm.model != nil }
        viewModel.waitingForm.model?.setValue("a@b.com", for: "email")

        await viewModel.waitingForm.save()

        #expect(provider.expireCount == 1)
        #expect(viewModel.livechatSessionEnded)
        try await eventually { viewModel.livechatStatus == .inactive && viewModel.waitingForm.model == nil }
    }

    @Test("a 401 while loading ends the chat")
    func expiredLoadEndsChat() async throws {
        let (viewModel, service, provider) = try self.makeSUT(fetchSession: {
            throw ChatServiceError.sessionExpired
        })
        service.livechatState = LivechatState(status: .waiting)

        viewModel.startLivechat(with: try Self.config())

        try await eventually { viewModel.livechatSessionEnded }
        #expect(provider.expireCount == 1)
        #expect(viewModel.waitingForm.model == nil)
    }

    @Test("a 422 marks the fields and keeps the card; another failure shows the banner")
    func failedSaves() async throws {
        let failure = Recorder<ChatServiceError>()
        let (viewModel, service, _) = try self.makeSUT(patchFormValues: { _, _ in
            let error = failure.values.isEmpty
                ? ChatServiceError.validation(
                    message: "Please fix the highlighted fields.",
                    params: [ValidationError(field: "values.email", message: "value must be a valid email address")]
                )
                : ChatServiceError.transport(.http(.unhandled(status: 500, body: Data())))
            failure.record(error)
            throw error
        })
        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { viewModel.waitingForm.model != nil }
        let model = try #require(viewModel.waitingForm.model)
        model.setValue("nope@x.y", for: "email")

        await viewModel.waitingForm.save()
        #expect(model.fieldErrors["email"] == L10n.formFieldRejected.string)

        model.setValue("a@b.com", for: "email")
        await viewModel.waitingForm.save()
        #expect(model.phase == .failed(L10n.sessionFormFailed.string))
        #expect(model.bannerError?.accessibilityID == "livechat.waitingForm.failed")
        #expect(viewModel.waitingForm.model != nil)
    }

    @Test("a form with only file fields shows no card")
    func fileOnlyFormShowsNoCard() async throws {
        let fetches = Recorder<String>()
        let (viewModel, service, _) = try self.makeSUT(fetchForm: { id in
            fetches.record(id)
            return try Self.definition(#"[{ "key": "photo", "label": "Photo", "type": "file", "required": true }]"#)
        })

        try await self.start(viewModel, in: .waiting, on: service)

        try await eventually { fetches.count == 1 }
        #expect(viewModel.waitingForm.model == nil)
    }

    @Test("a session that ends through a send or a history load drops the card", arguments: [true, false])
    func otherExpiryPathsDropCard(throughSend: Bool) async throws {
        let provider = StubChatProviding(sendFailure: throughSend ? .sessionExpired : nil)
        provider.loadOlderError = throughSend ? nil : ChatServiceError.sessionExpired
        let (viewModel, service, _) = try self.makeSUT(provider: provider)
        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { viewModel.waitingForm.model != nil }

        if throughSend {
            viewModel.currentMessage = "hi"
            await #expect(throws: ChatView.SessionEnded.self) { try await viewModel.send() }
        } else {
            await #expect(throws: ChatView.SessionEnded.self) { try await viewModel.loadOlder() }
        }

        #expect(viewModel.waitingForm.model == nil)
    }

    // MARK: Form model

    @Test(
        "a required field no save could fill means no card",
        arguments: [
            #"{ "key": "photo", "label": "Photo", "type": "file", "required": true }"#,
            #"{ "key": "sign", "label": "Signature", "type": "signature", "required": true }"#,
            #"""
            {
              "key": "extra", "label": "Extra", "required": true,
              "visible_when": [{ "field": "email", "operator": "equals", "value": "x@y.co" }]
            }
            """#
        ]
    )
    func unfillableRequiredFieldMeansNoCard(field: String) throws {
        let definition = try Self.definition(#"[{ "key": "email", "label": "Email", "type": "email" }, \#(field)]"#)

        #expect(WaitingFormModel.cardFields(from: definition) == nil)
    }

    @Test("optional file and unknown-type fields are left out and don't block saving")
    func optionalUnshownFieldsAreLeftOut() throws {
        let model = WaitingFormModel(definition: try Self.definition(#"""
        [
          { "key": "photo", "label": "Photo", "type": "file" },
          { "key": "sign", "label": "Signature", "type": "signature" },
          { "key": "email", "label": "Email", "type": "email" }
        ]
        """#, minFilled: 1))

        model.setValue("a@b.com", for: "email")

        #expect(model.form.fields.map(\.key) == ["email"])
        #expect(model.canSave)
        #expect(model.validate())
        #expect(model.valuesForPatch() == ["email": "a@b.com"])
    }

    @Test("a server error for a field a condition hides shows on the banner")
    func hiddenFieldErrorJoinsBanner() throws {
        let model = WaitingFormModel(definition: try Self.definition(#"""
        [
          { "key": "kind", "label": "Kind", "type": "dropdown", "options": ["a", "other"] },
          {
            "key": "extra", "label": "Extra",
            "visible_when": [{ "field": "kind", "operator": "equals", "value": "other" }]
          }
        ]
        """#))
        model.setValue("a", for: "kind")

        model.applyServerErrors(params: [ValidationError(field: "values.extra", message: "extra is required")])

        #expect(model.fieldErrors.isEmpty)
        #expect(model.formError == L10n.formSubmitFailed.string)
    }

    @Test("saving is offered only when the draft differs from what the session holds")
    func saveNeedsChanges() throws {
        let model = WaitingFormModel(
            definition: try Self.definition(Self.fields),
            sessionValues: try Self.session(#"[{ "key": "email", "value": "a@b.com" }]"#).values
        )
        #expect(!model.canSave)

        model.setValue("c@d.com", for: "email")
        #expect(model.canSave)

        model.setValue("a@b.com", for: "email")
        #expect(!model.canSave)
    }

    @Test("a saved field a condition now hides isn't sent, and the server keeps its value")
    func hiddenSavedFieldIsNotSent() throws {
        let model = WaitingFormModel(
            definition: try Self.definition(#"""
            [
              { "key": "kind", "label": "Kind", "type": "dropdown", "options": ["a", "other"] },
              {
                "key": "extra", "label": "Extra",
                "visible_when": [{ "field": "kind", "operator": "equals", "value": "other" }]
              }
            ]
            """#),
            sessionValues: try Self.session(#"""
            [{ "key": "kind", "value": "other" }, { "key": "extra", "value": "details" }]
            """#).values
        )

        model.setValue("a", for: "kind")

        #expect(model.valuesForPatch() == ["kind": "a"])
        #expect(model.canSave)
    }

    @Test("duplicate session keys keep the last value")
    func duplicateSessionKeys() throws {
        let model = WaitingFormModel(
            definition: try Self.definition(Self.fields),
            sessionValues: try Self.session(#"""
            [{ "key": "email", "value": "first@example.com" }, { "key": "email", "value": "last@example.com" }]
            """#).values
        )

        #expect(model.values["email"] == "last@example.com")
    }

    @Test("the PATCH body drops blank and hidden fields")
    func patchDropsBlanksAndHidden() throws {
        let model = WaitingFormModel(definition: try Self.definition(#"""
        [
          { "key": "kind", "label": "Kind", "type": "dropdown", "options": ["a", "other"] },
          {
            "key": "extra", "label": "Extra",
            "visible_when": [{ "field": "kind", "operator": "equals", "value": "other" }]
          },
          { "key": "email", "label": "Email", "type": "email" }
        ]
        """#))

        model.setValue("a", for: "kind")
        model.setValue("secret", for: "extra")
        model.setValue("  ", for: "email")

        #expect(model.valuesForPatch() == ["kind": "a"])
    }

    @Test("min_filled_fields blocks a save until enough fields are filled")
    func minFilledBlocks() throws {
        let model = WaitingFormModel(definition: try Self.definition(Self.fields, minFilled: 2))
        model.setValue("a@b.com", for: "email")

        #expect(model.canSave)
        #expect(!model.validate())
        #expect(model.bannerError?.accessibilityID == "livechat.waitingForm.validation")

        model.setValue("ORDER-1", for: "order_number")
        #expect(model.validate())
    }
}

private extension ChatViewModelWaitingFormTests {

    static let fields = #"""
    [
      { "key": "email", "label": "Email", "type": "email" },
      { "key": "order_number", "label": "Order", "type": "text" }
    ]
    """#

    func makeSUT(
        fetchForm: WaitingFormController.FormFetcher? = nil,
        fetchSession: WaitingFormController.SessionFetcher? = nil,
        patchFormValues: @escaping WaitingFormController.ValuesPatcher = { _, _ in throw CancellationError() },
        provider: StubChatProviding = StubChatProviding()
    ) throws -> (viewModel: ChatView.ViewModel, service: MockChatService, provider: StubChatProviding) {
        let service = MockChatService()
        let definition = try Self.definition(Self.fields)
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            fetchForm: fetchForm ?? { _ in definition },
            fetchSession: fetchSession ?? { try Self.session("[]") },
            patchFormValues: patchFormValues,
            // Ends the poll loop at its first wait, so only the reads a test triggers run.
            livechat: LivechatSession(service: service) { _ in throw CancellationError() }
        )
        viewModel.waitingForm.configure(formId: "livechatWaitingContact")
        return (viewModel, service, provider)
    }

    /// Starts livechat on a session in `status`, as the bootstrap read finds it.
    func start(
        _ viewModel: ChatView.ViewModel,
        in status: LivechatState.Status,
        on service: MockChatService
    ) async throws {
        service.livechatState = LivechatState(status: status)
        viewModel.startLivechat(with: try Self.config())
        try await eventually { viewModel.livechatStatus == status }
    }

    static func config() throws -> LivechatConfig {
        try LivechatFixtures.decoder.decode(
            LivechatConfig.self,
            from: Data(#"{"enabled":true,"configured":true,"availability_status":"live"}"#.utf8)
        )
    }

    nonisolated static func definition(_ fields: String, minFilled: Int = 0) throws -> ChatFormDefinition {
        try LivechatFixtures.decoder.decode(ChatFormDefinition.self, from: Data("""
        {
          "form_id": "livechatWaitingContact",
          "name": "Waiting",
          "fields": \(fields),
          "min_filled_fields": \(minFilled)
        }
        """.utf8))
    }

    nonisolated static func session(_ values: String) throws -> ChatSessionState {
        try LivechatFixtures.decoder.decode(ChatSessionState.self, from: Data(#"{"values": \#(values)}"#.utf8))
    }
}
