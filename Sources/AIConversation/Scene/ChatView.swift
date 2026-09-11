//
//  ChatView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import PhotosUI
import AIConversationEngine

/// The SDK's main screen — the chat UI returned by `AIChat.makeView()`.
///
/// Layout lives in sibling extension files: `+Window` (navigation chrome, notices, composer),
/// `+Conversation` (the flow-specific list and header) and `+Turns` (per-response rendering).
/// View state is declared here and is internal so those extensions can read and bind it.
struct ChatView: View {

    let viewModel: ViewModel

    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) var colorScheme
    @FocusState var inputFocused: Bool

    @State var showSessionEndedAlert = false
    @State var privacyDestination: PrivacyDataDestination?
    @State var isLoading = false
    @State var photoPickerItem: PhotosPickerItem?
    @State var isPhotoPickerPresented = false
    /// Where the *next* pick lands. Set before presenting and deliberately **not** cleared on
    /// dismissal: the picker updates `selection` and flips `isPresented` in the same gesture and
    /// SwiftUI does not promise the order, so routing state must outlive presentation state.
    @State var photoDestination: PhotoDestination = .composer
    /// Measured height of the overlaid composer so the list can keep the last turn above it.
    @State var composerHeight: CGFloat = 0

    /// Where a photo pick should land — composer chip or an upload-prompt card.
    enum PhotoDestination: Equatable {
        case composer
        case imageUpload(RequestImageUpload)
    }

    var appearance: ChatAppearance {
        let base = self.viewModel.appearance ?? .default
        return base.with(colorScheme: self.viewModel.resolvedScheme(environment: self.colorScheme))
    }

    /// Keyboard / pickers match the painted palette. Unset until ready so loading stays
    /// on the environment (no forced-light flash, no forced-dark chrome on a cloned theme).
    private var preferredChrome: ColorScheme? {
        guard self.viewModel.phase == .ready else { return nil }
        return self.viewModel.preferredColorScheme(for: self.appearance)
    }

    /// The one way to open the picker: fix the route, then present.
    func pickPhoto(for destination: PhotoDestination) {
        self.photoDestination = destination
        self.isPhotoPickerPresented = true
    }

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        self.content
            .modifier(LoadingOverlay(isLoading: self.isLoading))
            .task { await self.viewModel.start() }
            .environment(\.appearance, self.appearance)
            .environment(\.imageLoader, self.viewModel.imageLoader)
            .preferredColorScheme(self.preferredChrome)
            .photosPicker(
                isPresented: self.$isPhotoPickerPresented,
                selection: self.$photoPickerItem,
                matching: .images
            )
            .onChange(of: self.photoPickerItem) { _, item in
                guard let item else { return }
                self.photoPickerItem = nil
                let destination = self.photoDestination
                Task { await self.ingest(item, destination: destination) }
            }
    }
}

// MARK: - Phases

private extension ChatView {

    @ViewBuilder
    var content: some View {
        switch self.viewModel.phase {
        case .loading: self.loadingView
        case .ready: self.readyView
        case .failed: self.failedView
        }
    }

    var loadingView: some View {
        ProgressView()
            .tint(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }

    var readyView: some View {
        self.chatWindow
            .modifier(
                PrivacyDataSheetModifier(
                    destination: self.$privacyDestination,
                    onOpenPrivacy: {
                        if let url = self.viewModel.privacyPolicyURL {
                            self.openURL(url)
                        }
                    },
                    onExportData: { try await self.viewModel.exportMyData() },
                    onDiscardExport: { self.viewModel.discardExportFile() },
                    onDeleteData: { try await self.viewModel.delete() },
                    onSessionEnded: { self.showSessionEndedAlert = true }
                )
            )
            .alert(L10n.sessionEndedTitle.string, isPresented: self.$showSessionEndedAlert) {
                Button(L10n.sessionEndedDismiss.string, role: .cancel) { } // NO-OP
            } message: {
                Text(L10n.sessionEndedMessage)
            }
    }

    var failedView: some View {
        BootstrapErrorView(
            onRetry: {
                Task { await self.viewModel.start() }
            }
        )
    }
}

// MARK: - Session-bound actions

extension ChatView {

    /// Dismisses the keyboard and sends the current message; a failure means the session is gone.
    func send() {
        self.inputFocused = false
        Task { await self.withSessionAlert { try await self.viewModel.send() } }
    }

    /// Dismisses the keyboard and sends a suggestion-card or start-prompt chip's text; a failure
    /// means the session is gone.
    func send(prompt: String) {
        self.inputFocused = false
        Task { await self.withSessionAlert { try await self.viewModel.send(prompt: prompt) } }
    }

    /// Requests the next older page and reports how it went. A throw means the session is gone,
    /// so surface the ended alert — nothing was prepended, and there is nothing left to retry.
    func loadOlder() async -> HistoryLoadOutcome {
        var outcome = HistoryLoadOutcome.nothing
        await self.withSessionAlert { outcome = try await self.viewModel.loadOlder() }
        return outcome
    }

    /// Runs a session-bound action; surfaces the ended alert when the session is gone.
    func withSessionAlert(_ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            self.showSessionEndedAlert = true
        }
    }

    /// Loads the picked photo bytes and routes them to the composer or an upload prompt.
    func ingest(_ item: PhotosPickerItem, destination: PhotoDestination) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            self.viewModel.presentAttachmentFailure()
            return
        }
        switch destination {
        case .composer:
            await self.viewModel.ingestPickedPhoto(data)

        case .imageUpload(let marker):
            await self.viewModel.ingestPromptPhoto(data, marker: marker)
        }
    }
}
