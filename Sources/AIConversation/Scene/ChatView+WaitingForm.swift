//
//  ChatView+WaitingForm.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

extension ChatView {

    /// Newest-edge chrome: waiting-room session form and/or start-prompt chips.
    /// Same footer slot on topDown and bottomUp (newest is at the list end in both).
    @ViewBuilder
    var conversationEdgeChrome: some View {
        VStack(spacing: 0) {
            if self.viewModel.shouldShowWaitingForm, let model = self.viewModel.waitingFormModel {
                LivechatWaitingFormView(
                    model: model,
                    focus: self.$focusedFormField
                )
            }
            if self.viewModel.shouldShowStartPrompts {
                StartPromptsView(
                    prompts: self.viewModel.startPrompts,
                    onSelect: { self.send(prompt: $0) }
                )
            }
        }
    }

    var showsConversationEdgeChrome: Bool {
        self.viewModel.shouldShowWaitingForm || self.viewModel.shouldShowStartPrompts
    }

    /// Save stays above the composer so a tall field list never covers it.
    @ViewBuilder
    var waitingFormSaveChrome: some View {
        if self.viewModel.shouldShowWaitingForm, let model = self.viewModel.waitingFormModel {
            LivechatWaitingFormSaveChrome(model: model, onSave: { self.saveWaitingForm() })
        }
    }

    func saveWaitingForm() {
        Task {
            await self.withSessionAlert {
                try await self.viewModel.saveWaitingForm()
            }
        }
    }
}

extension ChatView.ViewModel {

    /// Whether the waiting-room form card should render.
    var shouldShowWaitingForm: Bool {
        self.livechat.status == .waiting && self.waitingFormModel != nil
    }

    /// Copies the waiting-form id from `/config` (first `livechat_waiting` row).
    func applyWaitingFormIdFromConfig(_ formId: String?) {
        self.waitingFormId = formId
    }

    /// Test seam — sets the waiting form id without `/config`.
    func setWaitingFormIdForTesting(_ formId: String?) {
        self.waitingFormId = formId
    }

    /// Test seam — installs a model without network fetch.
    func setWaitingFormModelForTesting(_ model: WaitingFormModel?) {
        self.waitingFormModel = model
    }

    /// Entering `.waiting` loads the form once; leaving waiting clears it.
    func updateWaitingFormForStatusChange(
        previous: LivechatState.Status,
        status: LivechatState.Status
    ) {
        if status != .waiting {
            self.clearWaitingForm()
            return
        }
        if previous != .waiting {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.loadWaitingFormIfNeeded()
                } catch is ChatView.SessionEnded {
                    self.sessionEnded = true
                } catch {
                    // Soft-fail already handled inside load.
                }
            }
        }
    }

    /// Soft-fail fetch (404 / transport) → no card. 401 → ``ChatView/SessionEnded``.
    func loadWaitingFormIfNeeded() async throws(ChatView.SessionEnded) {
        guard self.livechat.status == .waiting else { return }
        guard let formId = self.waitingFormId, !formId.isEmpty else { return }
        guard self.waitingFormModel == nil, !self.waitingFormLoadInFlight else { return }

        self.waitingFormLoadInFlight = true
        defer { self.waitingFormLoadInFlight = false }

        do {
            async let definitionTask = self.fetchForm(formId)
            async let sessionTask = self.fetchSession()
            let form = try await definitionTask
            let sessionState = try await sessionTask
            guard self.livechat.status == .waiting else { return }
            guard !WaitingFormModel.stringFields(from: form).isEmpty else { return }
            self.waitingFormModel = WaitingFormModel(
                definition: form,
                sessionValues: sessionState.values
            )
        } catch ChatServiceError.sessionExpired {
            self.waitingFormModel = nil
            throw ChatView.SessionEnded()
        } catch {
            self.waitingFormModel = nil
        }
    }

    /// Saves via `PATCH /forms/{id}/values`. 409 → hide; validation → per-field errors.
    func saveWaitingForm() async throws(ChatView.SessionEnded) {
        guard let model = self.waitingFormModel else { return }
        guard model.canSave else { return }
        guard model.validate() else { return }
        guard model.beginSaving() else { return }

        let values = model.valuesForPatch()
        guard !values.isEmpty else {
            model.markFailed(L10n.sessionFormFailed.string)
            return
        }

        do {
            let session = try await self.patchFormValues(model.definition.formId, values)
            for value in session.values {
                model.setValue(value.value, for: value.key)
            }
            model.markSaved()
        } catch ChatServiceError.sessionExpired {
            model.markFailed(L10n.sessionFormFailed.string)
            throw ChatView.SessionEnded()
        } catch ChatServiceError.conflict {
            self.clearWaitingForm()
        } catch ChatServiceError.validation(let message, let params) {
            model.applyServerErrors(params: params, formMessage: message)
        } catch {
            model.markFailed(L10n.sessionFormFailed.string)
        }
    }

    func clearWaitingForm() {
        self.waitingFormModel = nil
        self.waitingFormLoadInFlight = false
    }
}
