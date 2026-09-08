//
//  ChatViewModelWaitingFormTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine
import AIConversationCore

private let waitingFormDefinition = ChatFormDefinition(
    formId: "livechatWaitingContact",
    name: "Waiting",
    trigger: .livechatWaiting,
    fields: [
        FormField(key: "email", label: "Email", type: .email),
        FormField(key: "order_number", label: "Order", type: .text),
    ],
    minFilledFields: 1
)

@Suite("ChatView.ViewModel — livechat waiting form")
@MainActor
struct ChatViewModelWaitingFormTests {

    @Test("waiting loads form; active clears it; save does not hit /actions")
    func loadSaveAndHide() async throws {
        let actions = CallCounter()
        let patches = CallCounter()
        let vm = Self.makeVM(
            submitAction: { _ in
                actions.value += 1
                return SubmitActionResponse(submissionId: "x", confirmationText: nil)
            },
            fetchForm: { _ in waitingFormDefinition },
            fetchSession: { ChatSessionState() },
            patchFormValues: { _, values in
                patches.value += 1
                return ChatSessionState(values: values.map { ChatSessionValue(key: $0.key, value: $0.value) })
            }
        )
        vm.setWaitingFormIdForTesting("livechatWaitingContact")

        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .inactive,
            state: LivechatState(status: .waiting)
        ))
        try await Self.waitForModel(vm)
        #expect(vm.shouldShowWaitingForm == true)

        let model = try #require(vm.waitingFormModel)
        model.setValue("shopper@example.com", for: "email")
        try await vm.saveWaitingForm()
        #expect(model.isSaved == true)
        #expect(patches.value == 1)
        #expect(actions.value == 0)

        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .waiting,
            state: LivechatState(status: .active)
        ))
        #expect(vm.shouldShowWaitingForm == false)
        #expect(vm.waitingFormModel == nil)
    }

    @Test("prefill uses GET /session values; duplicate keys keep the last")
    func prefillFromSession() async throws {
        let vm = Self.makeVM(
            fetchForm: { _ in waitingFormDefinition },
            fetchSession: {
                ChatSessionState(values: [
                    ChatSessionValue(key: "email", value: "first@example.com"),
                    ChatSessionValue(key: "email", value: "shopper@example.com"),
                ])
            }
        )
        vm.setWaitingFormIdForTesting("livechatWaitingContact")
        vm.setLivechatStatusForTesting(.waiting)
        try await vm.loadWaitingFormIfNeeded()
        let model = try #require(vm.waitingFormModel)
        #expect(model.values["email"] == "shopper@example.com")
    }

    @Test("soft-fail load leaves no card and stays waiting")
    func softFailLoad() async throws {
        let vm = Self.makeVM(
            fetchForm: { _ in throw ChatServiceError.transport(.http(.unhandled(status: 404))) }
        )
        vm.setWaitingFormIdForTesting("livechatWaitingContact")
        vm.setLivechatStatusForTesting(.waiting)
        try await vm.loadWaitingFormIfNeeded()
        #expect(vm.waitingFormModel == nil)
        #expect(vm.shouldShowWaitingForm == false)
        #expect(vm.livechat.status == .waiting)
        #expect(vm.sessionEnded == false)
    }

    @Test("load 401 throws SessionEnded; snapshot path sets sessionEnded")
    func load401() async throws {
        let direct = Self.makeVM(
            fetchForm: { _ in throw ChatServiceError.sessionExpired }
        )
        direct.setWaitingFormIdForTesting("livechatWaitingContact")
        direct.setLivechatStatusForTesting(.waiting)
        do {
            try await direct.loadWaitingFormIfNeeded()
            Issue.record("expected SessionEnded")
        } catch is ChatView.SessionEnded {
            // expected
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
        #expect(direct.waitingFormModel == nil)

        let viaSnapshot = Self.makeVM(
            fetchForm: { _ in throw ChatServiceError.sessionExpired }
        )
        viaSnapshot.setWaitingFormIdForTesting("livechatWaitingContact")
        await viaSnapshot.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .inactive,
            state: LivechatState(status: .waiting)
        ))
        for _ in 0..<30 {
            if viaSnapshot.sessionEnded { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(viaSnapshot.sessionEnded == true)
        #expect(viaSnapshot.waitingFormModel == nil)
    }

    @Test("empty string fields → no card; file-only definition → no card")
    func emptyAndFileOnlySkipCard() async throws {
        let empty = ChatFormDefinition(
            formId: "empty",
            trigger: .livechatWaiting,
            fields: [],
            minFilledFields: 0
        )
        let emptyVM = Self.makeVM(fetchForm: { _ in empty })
        emptyVM.setWaitingFormIdForTesting("empty")
        emptyVM.setLivechatStatusForTesting(.waiting)
        try await emptyVM.loadWaitingFormIfNeeded()
        #expect(emptyVM.waitingFormModel == nil)

        let fileOnly = ChatFormDefinition(
            formId: "files",
            trigger: .livechatWaiting,
            fields: [FormField(key: "photo", label: "Photo", type: .file, required: true)],
            minFilledFields: 0
        )
        let fileVM = Self.makeVM(fetchForm: { _ in fileOnly })
        fileVM.setWaitingFormIdForTesting("files")
        fileVM.setLivechatStatusForTesting(.waiting)
        try await fileVM.loadWaitingFormIfNeeded()
        #expect(fileVM.waitingFormModel == nil)
    }

    @Test("required file field is stripped and does not block Save")
    func fileFieldDoesNotBlockSave() async throws {
        let definition = ChatFormDefinition(
            formId: "livechatWaitingContact",
            trigger: .livechatWaiting,
            fields: [
                FormField(key: "photo", label: "Photo", type: .file, required: true),
                FormField(key: "email", label: "Email", type: .email),
            ],
            minFilledFields: 1
        )
        let model = WaitingFormModel(definition: definition)
        #expect(model.form.fields.map(\.key) == ["email"])
        #expect(model.hasStringFields == true)
        model.setValue("a@b.com", for: "email")
        #expect(model.canSave == true)
        #expect(model.validate() == true)
        #expect(model.valuesForPatch() == ["email": "a@b.com"])
    }

    @Test("duplicate session keys do not crash; last value wins")
    func duplicateSessionKeys() {
        let model = WaitingFormModel(
            definition: waitingFormDefinition,
            sessionValues: [
                ChatSessionValue(key: "email", value: "first@example.com"),
                ChatSessionValue(key: "email", value: "last@example.com"),
            ]
        )
        #expect(model.values["email"] == "last@example.com")
    }

    @Test("valuesForPatch drops blanks and hidden fields")
    func patchDropsBlanksAndHidden() {
        let definition = ChatFormDefinition(
            formId: "livechatWaitingContact",
            trigger: .livechatWaiting,
            fields: [
                FormField(key: "kind", label: "Kind", type: .dropdown, options: ["a", "other"]),
                FormField(
                    key: "extra",
                    label: "Extra",
                    visibleWhen: [FormFieldCondition(field: "kind", value: "other")]
                ),
                FormField(key: "email", label: "Email", type: .email),
            ]
        )
        let model = WaitingFormModel(definition: definition)
        model.setValue("a", for: "kind")
        model.setValue("secret", for: "extra")
        model.setValue("  ", for: "email")
        #expect(model.valuesForPatch() == ["kind": "a"])
    }

    @Test("min_filled_fields blocks save; empty save does not PATCH")
    func minFilledBlocks() async throws {
        let patches = CallCounter()
        let definition = ChatFormDefinition(
            formId: "livechatWaitingContact",
            name: "Waiting",
            trigger: .livechatWaiting,
            fields: [
                FormField(key: "email", label: "Email", type: .email),
                FormField(key: "order_number", label: "Order", type: .text),
            ],
            minFilledFields: 2
        )
        let vm = Self.makeVM(
            patchFormValues: { _, _ in
                patches.value += 1
                return ChatSessionState()
            }
        )
        vm.setWaitingFormIdForTesting("livechatWaitingContact")
        let model = WaitingFormModel(definition: definition)
        model.setValue("a@b.com", for: "email")
        vm.setWaitingFormModelForTesting(model)
        vm.setLivechatStatusForTesting(.waiting)

        #expect(model.canSave == true)
        #expect(model.validate() == false)
        #expect(model.bannerError?.accessibilityID == "livechat.waitingForm.validation")
        try await vm.saveWaitingForm()
        #expect(patches.value == 0)

        model.setValue("ORDER-1", for: "order_number")
        #expect(model.validate() == true)
    }

    @Test("409 on save clears the card; 401 throws SessionEnded")
    func conflictAnd401() async throws {
        let conflictVM = Self.makeVM(
            patchFormValues: { _, _ in throw ChatServiceError.conflict }
        )
        conflictVM.setLivechatStatusForTesting(.waiting)
        let model = WaitingFormModel(definition: waitingFormDefinition)
        model.setValue("a@b.com", for: "email")
        conflictVM.setWaitingFormModelForTesting(model)
        try await conflictVM.saveWaitingForm()
        #expect(conflictVM.waitingFormModel == nil)

        let expiredVM = Self.makeVM(
            patchFormValues: { _, _ in throw ChatServiceError.sessionExpired }
        )
        expiredVM.setLivechatStatusForTesting(.waiting)
        let model2 = WaitingFormModel(definition: waitingFormDefinition)
        model2.setValue("a@b.com", for: "email")
        expiredVM.setWaitingFormModelForTesting(model2)
        do {
            try await expiredVM.saveWaitingForm()
            Issue.record("expected SessionEnded")
        } catch is ChatView.SessionEnded {
            // expected
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
        #expect(model2.bannerError?.accessibilityID == "livechat.waitingForm.failed")
    }

    @Test("save 422 applies per-field errors and keeps the card")
    func saveValidationKeepsCard() async throws {
        let vm = Self.makeVM(
            patchFormValues: { _, _ in
                throw ChatServiceError.validation(
                    message: "Check your answers",
                    params: [ValidationError(field: "email", message: "Invalid")]
                )
            }
        )
        vm.setLivechatStatusForTesting(.waiting)
        let model = WaitingFormModel(definition: waitingFormDefinition)
        model.setValue("a@b.com", for: "email")
        vm.setWaitingFormModelForTesting(model)
        try await vm.saveWaitingForm()
        #expect(vm.waitingFormModel != nil)
        #expect(vm.shouldShowWaitingForm == true)
        #expect(model.isSaved == false)
        #expect(model.phase == .editing)
        #expect(model.fieldErrors["email"] == "Invalid")
        #expect(model.formError == "Check your answers")
        #expect(model.bannerError?.accessibilityID == "livechat.waitingForm.validation")
    }

    @Test("non-409 transport error keeps the card and sets failed")
    func save500KeepsCard() async throws {
        let vm = Self.makeVM(
            patchFormValues: { _, _ in
                throw ChatServiceError.transport(.http(.unhandled(status: 500)))
            }
        )
        vm.setLivechatStatusForTesting(.waiting)
        let model = WaitingFormModel(definition: waitingFormDefinition)
        model.setValue("a@b.com", for: "email")
        vm.setWaitingFormModelForTesting(model)
        try await vm.saveWaitingForm()
        #expect(vm.waitingFormModel != nil)
        #expect(vm.shouldShowWaitingForm == true)
        #expect(model.isSaved == false)
        if case .failed = model.phase {
            // expected
        } else {
            Issue.record("expected phase .failed, got \(String(describing: model.phase))")
        }
        #expect(model.bannerError?.accessibilityID == "livechat.waitingForm.failed")
    }

    private static func makeVM(
        submitAction: ChatView.ViewModel.ActionSubmitter? = nil,
        fetchForm: ChatView.ViewModel.FormFetcher? = nil,
        fetchSession: ChatView.ViewModel.SessionFetcher? = nil,
        patchFormValues: ChatView.ViewModel.FormValuesPatcher? = nil
    ) -> ChatView.ViewModel {
        let vm = ChatView.ViewModel(
            service: ChatService(
                tokenProvider: { "t" },
                onResetConversation: { "t" },
                onDeleteData: {}
            ),
            contextProvider: nil,
            conversationFlow: .topDown,
            submitAction: submitAction,
            fetchForm: fetchForm,
            fetchSession: fetchSession ?? { ChatSessionState() },
            patchFormValues: patchFormValues
        )
        vm.attachProviderForTesting(StubChatProviding())
        vm.suppressLivechatNetwork = true
        return vm
    }

    private static func waitForModel(_ vm: ChatView.ViewModel) async throws {
        for _ in 0..<30 {
            if vm.waitingFormModel != nil { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("waiting form did not load")
    }
}

private final class CallCounter: @unchecked Sendable {
    var value = 0
}
