//
//  WaitingFormController.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Loads, shows and saves the livechat waiting-room form while the visitor is queued. The chat
/// view model passes it every livechat status and the screen's visibility; the card shows while
/// ``model`` is set.
@MainActor
@Observable
final class WaitingFormController {

    typealias FormFetcher = @Sendable (String) async throws -> ChatFormDefinition
    typealias SessionFetcher = @Sendable () async throws -> ChatSessionState
    typealias ValuesPatcher = @Sendable (String, [String: String]) async throws -> ChatSessionState

    /// The card's draft, once the form and the session's values have loaded while queued.
    private(set) var model: WaitingFormModel?

    @ObservationIgnored private let fetchForm: FormFetcher
    @ObservationIgnored private let fetchSession: SessionFetcher
    @ObservationIgnored private let patchValues: ValuesPatcher
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    /// Runs when a request finds the visitor session ended (401); see ``bind(onSessionExpired:)``.
    @ObservationIgnored private var onSessionExpired: (@MainActor () async -> Void)?
    /// The configured `livechat_waiting` form, from `/config`.
    @ObservationIgnored private var formId: String?
    @ObservationIgnored private var isWaiting = false
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var isVisible = true
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// This wait shows no card: the form has no field the card can show, or it can't be loaded.
    @ObservationIgnored private var hasNoCard = false
    /// Bumped whenever the card is cleared, so a load started before can't install a stale card.
    @ObservationIgnored private var generation = 0

    private static let firstRetry: Duration = .seconds(2)
    private static let maxRetry: Duration = .seconds(30)

    init(
        fetchForm: @escaping FormFetcher,
        fetchSession: @escaping SessionFetcher,
        patchValues: @escaping ValuesPatcher,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.fetchForm = fetchForm
        self.fetchSession = fetchSession
        self.patchValues = patchValues
        self.sleep = sleep
    }

    /// Sets what runs when a request finds the visitor session ended (401). The first handler
    /// stays.
    func bind(onSessionExpired handler: @escaping @MainActor () async -> Void) {
        guard self.onSessionExpired == nil else { return }
        self.onSessionExpired = handler
    }

    /// Takes the `livechat_waiting` form id from `/config`; nil when none is configured.
    func configure(formId: String?) {
        self.formId = formId
    }

    /// Follows the livechat status. While queued the card loads, and a transient failure is
    /// retried with backoff while the chat is on screen; any other status clears it.
    func statusChanged(to status: LivechatState.Status) {
        guard status == .waiting else {
            self.clear()
            return
        }
        self.isWaiting = true
        self.loadIfNeeded()
    }

    /// Pauses retries while the app is in the background.
    func setSceneActive(_ active: Bool) {
        self.isSceneActive = active
        self.loadIfNeeded()
    }

    /// Pauses retries while the chat is off screen.
    func setVisible(_ visible: Bool) {
        self.isVisible = visible
        self.loadIfNeeded()
    }

    /// Saves the card through `PATCH /forms/{id}/values`. A 422 marks the fields; a 409 means the
    /// visitor is no longer waiting and drops the card; a 401 ends the session; any other failure
    /// shows the card's banner. The result of a save the card was cleared during is dropped.
    func save() async {
        guard let model = self.model, model.canSave, model.validate(), model.beginSaving() else { return }
        let generation = self.generation
        let session: ChatSessionState
        do {
            session = try await self.patchValues(model.definition.formId, model.valuesForPatch())
        } catch {
            guard generation == self.generation else { return }
            await self.saveFailed(model, error: error)
            return
        }
        guard generation == self.generation else { return }
        model.markSaved(session)
    }

    /// Drops the card and stops a load in flight.
    func clear() {
        self.isWaiting = false
        guard self.model != nil || self.loadTask != nil || self.hasNoCard else { return }
        self.generation += 1
        self.loadTask?.cancel()
        self.loadTask = nil
        self.hasNoCard = false
        if self.model != nil {
            self.model = nil
        }
    }
}

private extension WaitingFormController {

    enum LoadResult {
        case loaded(WaitingFormModel)
        case noCard
        case expired
        case retry
    }

    var isOnScreen: Bool {
        self.isSceneActive && self.isVisible
    }

    func saveFailed(_ model: WaitingFormModel, error: any Error) async {
        switch error {
        case ChatServiceError.sessionExpired:
            model.markFailed()
            await self.onSessionExpired?()
        case ChatServiceError.conflict:
            // The poller publishes the status that replaced `waiting`.
            self.clear()
        case ChatServiceError.validation(_, let params):
            model.applyServerErrors(params: params)
        default:
            model.markFailed()
        }
    }

    func loadIfNeeded() {
        guard self.isWaiting, self.isOnScreen, self.model == nil, self.loadTask == nil, !self.hasNoCard,
              let formId = self.formId, !formId.isEmpty else { return }
        let generation = self.generation
        let sleep = self.sleep
        self.loadTask = Task { [weak self] in
            // `self` is re-acquired for each attempt, so the sleep between attempts holds no reference.
            var delay = Self.firstRetry
            while await self?.attempt(formId: formId, generation: generation) == true {
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
                delay = min(delay * 2, Self.maxRetry)
            }
        }
    }

    /// One load attempt; true when it should be retried. An attempt for a cleared card, or
    /// while the chat is off screen, ends the load, and coming back on screen starts a new one.
    func attempt(formId: String, generation: Int) async -> Bool {
        guard self.generation == generation else { return false }
        guard self.isOnScreen else {
            self.loadTask = nil
            return false
        }
        let result = await self.fetchModel(formId: formId)
        guard self.generation == generation else { return false }
        switch result {
        case .loaded(let model):
            self.model = model
        case .noCard:
            self.hasNoCard = true
        case .expired:
            self.loadTask = nil
            await self.onSessionExpired?()
            return false
        case .retry:
            return true
        }
        self.loadTask = nil
        return false
    }

    func fetchModel(formId: String) async -> LoadResult {
        let fetchForm = self.fetchForm
        let fetchSession = self.fetchSession
        async let definition = Self.outcome { try await fetchForm(formId) }
        async let session = Self.outcome { try await fetchSession() }
        let form = await definition
        let state = await session
        if case .success(let form) = form, case .success(let state) = state {
            guard WaitingFormModel.cardFields(from: form) != nil else { return .noCard }
            return .loaded(WaitingFormModel(definition: form, sessionValues: state.values))
        }
        // Either read can find the visitor session ended, which outranks the other read's failure.
        let errors = [Self.failure(of: form), Self.failure(of: state)].compactMap { $0 as? ChatServiceError }
        if errors.contains(where: { if case .sessionExpired = $0 { true } else { false } }) {
            return .expired
        }
        return errors.contains(where: \.isTransient) ? .retry : .noCard
    }

    /// Runs `work`, keeping its error in the result so both loads finish.
    static func outcome<Value: Sendable>(
        _ work: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }

    static func failure<Value>(of result: Result<Value, any Error>) -> (any Error)? {
        if case .failure(let error) = result { error } else { nil }
    }
}
