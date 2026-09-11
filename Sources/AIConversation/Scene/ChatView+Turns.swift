//
//  ChatView+Turns.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Per-turn rendering: one bot turn is a stack of responses (text, cards, chips, media, table);
/// one user turn is a stack of bubbles and attachments.
extension ChatView {

    func botTurn(
        _ responses: [ChatResponse],
        isStreaming: Bool,
        isLatestBotTurn: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(responses.enumerated()), id: \.offset) { index, response in
                self.botResponse(
                    response,
                    // Only the last bubble is the one being generated, animate border/typewrite just that.
                    isStreaming: isStreaming && index == responses.count - 1,
                    isFirstResponse: index == 0,
                    isLastResponse: index == responses.count - 1 && !isStreaming,
                    isLatestBotTurn: isLatestBotTurn
                )
            }
        }
    }

    func userTurn(_ contents: [UserContent]) -> some View {
        VStack(alignment: .trailing, spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(contents.enumerated()), id: \.offset) { _, content in
                self.userContent(content)
            }
        }
    }

    // MARK: Bot responses

    @ViewBuilder
    private func botResponse(
        _ response: ChatResponse,
        isStreaming: Bool,
        isFirstResponse: Bool,
        isLastResponse: Bool,
        isLatestBotTurn: Bool
    ) -> some View {
        switch response {
        case .text(let text):
            self.textResponse(text, isStreaming: isStreaming)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .placeholder(let text):
            self.placeholderTextResponse(text, isStreaming: isStreaming)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .products(let cards):
            ProductGridView(
                cards: cards,
                openLabel: self.viewModel.productOpenLabel,
                cartEnabled: self.viewModel.cartEnabledByConfig,
                onAddToCart: self.viewModel.productAddToCart
            )
            .modifier(self.blockSpacing(isFirst: isFirstResponse, isLast: isLastResponse))

        case .suggestions(let cards):
            SuggestionGridView(cards: cards, onSelect: { self.send(prompt: $0) })
                .disabled(self.viewModel.isStreaming)
                .modifier(self.blockSpacing(isFirst: isFirstResponse, isLast: isLastResponse))

        case .quickReplies(let replies):
            // Only the newest bot turn's replies are actionable — older ones are gone, not
            // greyed out, so the transcript does not fill with chips that look tappable.
            if isLatestBotTurn {
                QuickRepliesView(replies: replies, onSelect: { self.send(prompt: $0) })
                    .disabled(self.viewModel.isStreaming)
                    .modifier(self.blockSpacing(isFirst: isFirstResponse, isLast: isLastResponse))
            }

        case .requestImageUpload(let marker):
            // Only reaches the view when the host offers attachments — the provider drops the
            // marker at ingestion otherwise, so a marker-only message leaves no empty row.
            ImageUploadPromptView {
                self.pickPhoto(for: .imageUpload(marker))
            }
            .disabled(!self.viewModel.canAttach)
            .modifier(self.blockSpacing(isFirst: isFirstResponse, isLast: isLastResponse))

        case .image(let image):
            MessageImageView(image: image)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .file(let file):
            MessageFileView(file: file)
                .modifier(RelativeWidth(0.70, alignment: .leading))
                .modifier(AvatarImage(image: self.viewModel.avatar, edge: .leading))

        case .table(let content):
            TableView(content: content)
                .modifier(self.blockSpacing(isFirst: isFirstResponse, isLast: isLastResponse))
        }
    }

    /// Full-width blocks (grids, chips, tables) sit apart from the bubbles around them; the
    /// outer edges of a turn stay flush.
    private func blockSpacing(isFirst: Bool, isLast: Bool) -> BlockSpacing {
        BlockSpacing(
            top: isFirst ? 0 : self.appearance.spacing.units(9),
            bottom: isLast ? 0 : self.appearance.spacing.units(9)
        )
    }

    private func placeholderTextResponse(_ text: AttributedString, isStreaming: Bool) -> some View {
        BotBubble(text: text)
            .modifier(WaveEffect())
            .modifier(ThinkingBorderEffect(isActive: isStreaming, shape: Rectangle()))
    }

    private func textResponse(_ text: AttributedString, isStreaming: Bool) -> some View {
        BotBubble(text: text)
            .modifier(TypewriterEffect(text: text, isActive: isStreaming))
            .modifier(ThinkingBorderEffect(isActive: isStreaming, shape: Rectangle()))
    }

    // MARK: User content

    @ViewBuilder
    private func userContent(_ content: UserContent) -> some View {
        switch content {
        case .text(let text):
            UserBubble(text: text)
                .modifier(RelativeWidth(0.70, alignment: .trailing))

        case .image(let image):
            MessageImageView(image: image)
                .modifier(RelativeWidth(0.70, alignment: .trailing))

        case .file(let file):
            MessageFileView(file: file)
                .modifier(RelativeWidth(0.70, alignment: .trailing))
        }
    }
}

/// Vertical padding for a full-width block inside a bot turn.
private struct BlockSpacing: ViewModifier {
    let top: CGFloat
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.bottom, self.bottom)
            .padding(.top, self.top)
    }
}
