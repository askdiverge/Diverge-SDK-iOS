//
//  ChatView+Conversation.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// The conversation list — picks the flow-specific container and feeds it header, turns and
/// the start-prompt footer.
extension ChatView {

    func chat(from snapshot: ConversationSnapshot) -> some View {
        self.conversationList(from: snapshot)
            .scrollDismissesKeyboard(.interactively)
            .modifier(
                DismissKeyboardOnTap(
                    isActive: self.inputFocused,
                    onDismiss: {
                        self.inputFocused = false
                        self.viewModel.dismissNotice()
                    })
            )
    }

    /// layout whichever flow is configured.
    @ViewBuilder
    private func conversationList(from snapshot: ConversationSnapshot) -> some View {
        /// The `List`-backed flows don't perform on macOS, so the Mac stays on the `ScrollView`-backed
#if os(macOS)
        ConversationView(
            snapshot: snapshot,
            isInputFocused: self.inputFocused,
            composerClearance: self.composerHeight,
            onLoadOlder: self.loadOlder,
            content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
            header: { self.chatHeader },
            footer: { self.conversationEdgeChrome },
            showsFooter: self.showsConversationEdgeChrome
        )
        .equatable()
#else
        switch self.viewModel.conversationFlow {
        case .topDown:
            ConversationTopFlowingList(
                snapshot: snapshot,
                isInputFocused: self.inputFocused,
                composerClearance: self.composerHeight,
                onLoadOlder: self.loadOlder,
                content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
                header: { self.chatHeader },
                footer: { self.conversationEdgeChrome },
                showsFooter: self.showsConversationEdgeChrome
            )
            .equatable()

        case .bottomUp:
            ConversationBottomFlowingList(
                snapshot: snapshot,
                isInputFocused: self.inputFocused,
                composerClearance: self.composerHeight,
                onLoadOlder: self.loadOlder,
                content: { self.turnView(for: $0, streamingTurnID: snapshot.streamingTurnID) },
                header: { self.chatHeader },
                footer: { self.conversationEdgeChrome },
                showsFooter: self.showsConversationEdgeChrome
            )
            .equatable()
        }
#endif
    }

    @ViewBuilder
    private func turnView(for turn: Identified<ConversationSnapshot.Turn>, streamingTurnID: UUID?) -> some View {
        switch turn.model {
        case .bot(let responses):
            self.botTurn(
                responses,
                isStreaming: turn.id == streamingTurnID,
                isLatestBotTurn: self.viewModel.isLatestBotTurn(turn.id)
            )

        case .user(let bubbles):
            self.userTurn(bubbles)

        case .system(let responses):
            SystemNoteRow(responses: responses)
        }
    }

    private var chatHeader: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(6)) {
            if let logo = self.viewModel.logo {
                logo.image
                    .resizable()
                    .scaledToFit()
                    .frame(height: self.appearance.spacing.units(10))
                    .frame(maxWidth: .infinity, alignment: logo.alignment)
            }

            if let subtitle = self.viewModel.subtitle {
                ChatHeader(subtitle: subtitle)
            }
        }
    }

    /// Start-prompt chips below the conversation (when configured and not yet chatting).
    @ViewBuilder
    private var conversationEdgeChrome: some View {
        if self.viewModel.shouldShowStartPrompts {
            StartPromptsView(
                prompts: self.viewModel.startPrompts,
                onSelect: { self.send(prompt: $0) }
            )
        }
    }

    private var showsConversationEdgeChrome: Bool {
        self.viewModel.shouldShowStartPrompts
    }
}
