//
//  ChatView+ViewModel.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import AIConversationEngine

extension ChatView {

    /// Observable state for the main screen. Coordinates the chat service facade
    @MainActor
    @Observable
    final class ViewModel {

        enum Phase {
            case loading, ready, failed
        }

        private(set) var phase: Phase = .loading
        private(set) var appearance: ChatAppearance?

        private(set) var name = ""
        private(set) var subtitle: Subtitle?
        private(set) var privacyPolicyURL: URL?
        private(set) var avatar: Image?
        private(set) var logo: HeaderLogo?
        private(set) var notice: Notice?

        /// Shared loader for remote imagery injected into the view environment.
        @ObservationIgnored let imageLoader: ImageLoader
        @ObservationIgnored let conversationFlow: AIChat.ConversationFlow
        @ObservationIgnored private let service: ChatService
        @ObservationIgnored private let pageContext: @Sendable () async -> String?
        @ObservationIgnored private var provider: (any ChatProviding)?
        @ObservationIgnored private let submitAction: ActionSubmitter
        @ObservationIgnored private let fetchForm: FormFetcher

        private(set) var snapshot: ConversationSnapshot?
        /// Drafts of the conversation's forms by `part_id`, created when a snapshot first brings
        /// the form so a draft survives list recycling.
        private(set) var formModels: [String: FormSubmissionModel] = [:]
        var currentMessage = ""

        /// Submits a marker-triggered action. Defaults to ``ChatService/submitAction``; tests
        /// inject a stub so form success / failure paths do not need a live network.
        typealias ActionSubmitter = @Sendable (SubmitActionRequest) async throws -> SubmitActionResponse

        /// Fetches a form definition. Defaults to ``ChatService/fetchForm``.
        typealias FormFetcher = @Sendable (String) async throws -> ChatFormDefinition

        init(
            service: ChatService,
            contextProvider: (@Sendable () async -> String?)?,
            conversationFlow: AIChat.ConversationFlow,
            submitAction: ActionSubmitter? = nil,
            fetchForm: FormFetcher? = nil
        ) {
            self.service = service
            self.pageContext = { await contextProvider?() }
            self.conversationFlow = conversationFlow
            self.submitAction = submitAction ?? { request in
                try await service.submitAction(request)
            }
            self.fetchForm = fetchForm ?? { id in
                try await service.fetchForm(id: id)
            }
            // Product/table imagery fills ~half-width, ~800px covers 3x.
            self.imageLoader = ImageLoader(maxPixelSize: 800) { try await service.fetchData($0) }
        }

        /// Bootstraps once, then no-ops on re-entry
        /// (e.g. the view reappearing) so the live session survives.
        func start() async {
            guard self.provider == nil else { return }
            await self.bootstrap()
        }

        /// Config → provider → snapshot stream → first history page.
        /// A config failure is surfaced on `phase` (retry re-enters here),
        /// a history failure is non-fatal.
        private func bootstrap() async {
            self.phase = .loading

            do {
                let config = try await self.service.fetchConfig()
                self.avatar = await self.loadImage(config.display.avatar.url, maxPixelSize: 200)
                self.logo = await self.loadImage(config.theme.header.logo.url, maxPixelSize: 600)
                    .map { HeaderLogo(image: $0, alignment: config.theme.header.alignment) }
                let fontFamily = await FontLoader.loadFamily(
                    url: config.theme.font.ios.assetUrl,
                    sha256: config.theme.font.ios.sha256,
                    format: config.theme.font.ios.format,
                    fetch: { [service = self.service] in try await service.fetchData($0) }
                )
                self.appearance = ChatAppearance(config, fontFamily: fontFamily)
                self.name = config.display.name
                self.subtitle = config.display.subtitle.map { Subtitle($0) }
                self.privacyPolicyURL = config.display.privacyPolicyUrl

                let provider = ChatProvider(
                    service: self.service,
                    pageContext: self.pageContext,
                    welcomeMessage: config.display.welcomeMessage
                )

                self.provider = provider
                self.observe(provider)

                try? await provider.loadOlder()
                self.phase = .ready

            } catch {
                self.phase = .failed
            }
        }

        /// Sends a user message. Recoverable failures (busy, retryable) bounce inline as a notice so
        /// the input stays stateless; a 401 ends the session and escapes as ``SessionEnded`` for the
        /// view to alert on.
        func send() async throws(SessionEnded) {
            if self.notice?.edge == .bottom { self.dismissNotice() }
            let text = self.currentMessage

            guard let provider = self.provider, !text.isEmpty else { return }

            do {
                self.currentMessage = ""
                try await provider.send(text)

            } catch {
                switch error {
                case .busy(.streaming):
                    self.currentMessage = text
                    self.present(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))

                case .busy(.operation):
                    break // NO-OP for now

                case .retry(popped: let lastMessage, body: let body):
                    self.currentMessage = lastMessage
                    self.present(Notice(edge: .bottom, message: body ?? L10n.noticeSendFailed.string, autoDismiss: nil))

                case .sessionExpired:
                    throw SessionEnded()
                }
            }
        }

        /// Whether a form card in the given bot turn may still be filled — only the newest bot
        /// turn's forms are actionable (the server rejects older `part_id`s).
        func isFormEditable(inBotTurn turnID: UUID) -> Bool {
            self.snapshot?.lastBotTurnID == turnID
        }

        /// Sets a text or dropdown answer on the draft of form `partId`.
        func setFormValue(_ value: String, for key: String, inForm partId: String) {
            self.formModels[partId]?.setValue(value, for: key)
        }

        /// Fetches the definition of a thin custom form again after the first fetch failed.
        func reloadFormDefinition(partId: String) {
            guard
                let model = self.formModels[partId], model.hydrationFailed,
                case .custom(let formId, _, _, _) = model.form.kind
            else { return }
            self.hydrateCustomForm(partId: partId, formId: formId)
        }

        /// Validates and submits the form identified by `partId`. Surfaces session expiry;
        /// other failures land on the form card. A no-op for unknown ids, drafts that fail
        /// validation, and forms already submitting or submitted.
        func submitForm(partId: String) async throws(SessionEnded) {
            guard let model = self.formModels[partId], !model.isSubmitting, !model.isSubmitted else { return }
            guard self.formModels[partId]?.validate() == true else { return }
            guard let request = model.buildRequest() else {
                self.formModels[partId]?.markFailed()
                return
            }
            guard self.formModels[partId]?.beginSubmitting() == true else { return }

            do {
                let response = try await self.submitAction(request)
                let text = FormSubmissionModel.confirmation(server: response.confirmationText, form: model.form)
                self.formModels[partId]?.markSubmitted(confirmation: text)
            } catch ChatServiceError.sessionExpired {
                self.formModels[partId]?.markFailed()
                throw SessionEnded()
            } catch ChatServiceError.validation(let message, let params) {
                self.formModels[partId]?.applyServerErrors(params: params, formMessage: message)
            } catch {
                self.formModels[partId]?.markFailed()
            }
        }

        /// Loads the next older page of history. A recoverable failure surfaces as a top notice;
        /// a 401 ends the session and escapes as ``SessionEnded`` for the view to alert on.
        func loadOlder() async throws(SessionEnded) {
            if self.notice?.edge == .top { self.dismissNotice() }

            do {
                try await self.provider?.loadOlder()

            } catch ChatServiceError.sessionExpired {
                throw SessionEnded()

            } catch {
                self.present(Notice(
                    edge: .top,
                    message: L10n.noticeHistoryLoadFailed.string,
                    autoDismiss: .seconds(4)
                ))
            }
        }

        /// Resets the conversation.
        func reset() async {
            do {
                try await self.provider?.reset()
            } catch {
                // A failed reset leaves the conversation, and its form drafts, as they were.
                return
            }
            self.formModels = [:]
        }

        /// Request deletion of visitor data and end the session. Rethrows so the delete sheet can act on the
        /// hook's suspension point — success dismisses it, a failure leaves it open for the host.
        func delete() async throws(DeletionFailed) {
            do {
                try await self.provider?.delete()
            } catch {
                throw DeletionFailed()
            }
            self.formModels = [:]
        }

        /// Test seam — attach a stub provider without bootstrapping `/config`.
        func attachProviderForTesting(_ provider: some ChatProviding) {
            self.provider = provider
            self.observe(provider)
        }

        /// Pre-loads a config image once, downsampled, so it isn't re-fetched during rendering.
        private func loadImage(_ url: URL?, maxPixelSize: CGFloat) async -> Image? {
            guard
                let url,
                let data = try? await self.service.fetchData(url)
            else {
                return nil
            }
            return RemoteImage.decode(data, maxPixelSize: maxPixelSize)
        }

        /// Mirrors the provider's latest-wins snapshots onto the main actor, preparing a draft for
        /// each form a snapshot brings before the view renders it.
        private func observe(_ provider: some ChatProviding) {
            let stream = provider.stream
            Task { [weak self] in
                for await snapshot in stream {
                    self?.prepareForms(in: snapshot)
                    self?.snapshot = snapshot
                }
            }
        }

        /// Creates a draft for each form `snapshot` brings for the first time. A thin custom
        /// `show_form` (no inline fields) fills in from `GET …/forms/{id}`.
        private func prepareForms(in snapshot: ConversationSnapshot) {
            for turn in snapshot.incoming {
                for case .form(let form) in turn.model where self.formModels[form.partId] == nil {
                    self.formModels[form.partId] = FormSubmissionModel(form: form)
                    if case .custom(let formId, _, _, _) = form.kind, form.fields.isEmpty {
                        self.hydrateCustomForm(partId: form.partId, formId: formId)
                    }
                }
            }
        }

        private func hydrateCustomForm(partId: String, formId: String) {
            self.formModels[partId]?.beginHydrating()
            Task { [weak self, fetchForm = self.fetchForm] in
                do {
                    let definition = try await fetchForm(formId)
                    self?.formModels[partId]?.applyHydratedDefinition(definition)
                } catch {
                    self?.formModels[partId]?.failHydrating()
                }
            }
        }

        private func present(_ notice: Notice) {
            guard notice != self.notice else { return }
            self.notice = notice
            guard let delay = notice.autoDismiss else { return }
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard self?.notice == notice else { return }
                self?.notice = nil
            }
        }

        func dismissNotice() {
            self.notice = nil
        }
    }
}
