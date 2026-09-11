//
//  ChatView+Window.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Navigation chrome around the conversation: toolbar, banner strip, notices and the composer.
extension ChatView {

    var chatWindow: some View {
        NavigationStack {
            Group {
                if let snapshot = self.viewModel.snapshot {
                    self.chat(from: snapshot)
                }
            }
            .navigationTitle(self.viewModel.name)
            .toolbarTitleDisplayMode(.inline)
#if os(iOS)
            .toolbarBackground(self.appearance.theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
            .toolbar {
                if self.viewModel.showsCloseButton {
                    self.closeToolbarItem
                }
                self.resetToolbarItem
            }
        }
        // Input sits outside the NavigationStack. The conversation List can collapse
        // in-stack `safeAreaInset`s to zero height on some iOS hosts; chrome outside
        // the stack stays visible.
        .safeAreaInset(edge: .bottom) {
            self.inputBar
                .measuringComposerHeight(self.$composerHeight)
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                self.topNotice
                if !self.viewModel.visibleBanners.isEmpty {
                    ChatBannerStrip(
                        banners: self.viewModel.visibleBanners,
                        onDismiss: { self.viewModel.dismissBanner($0) }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: self.viewModel.visibleBanners.map(\.contentFingerprint))
        }
        .background(self.appearance.theme.background)
        .animation(.default, value: self.viewModel.notice)
        .onChange(of: self.inputFocused) { _, focused in
            if focused, self.viewModel.notice?.edge == .bottom {
                self.viewModel.dismissNotice()
            }
        }
        .onChange(of: self.viewModel.sessionEnded) { _, ended in
            if ended { self.showSessionEndedAlert = true }
        }
    }

    // MARK: Toolbar

    /// Close hands off to the host immediately (no rating overlay).
    private func requestClose() {
        self.inputFocused = false
        self.viewModel.onClose?()
    }

    private func reset() {
        Task {
            self.isLoading = true
            await self.viewModel.reset()
            self.isLoading = false
        }
    }

    private var closeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                self.requestClose()
            } label: {
                HeaderToolbarIcon(symbol: ChatAppearance.Symbol.close)
            }
            .accessibilityLabel(L10n.chatClose.string)
            .accessibilityIdentifier("chat.close")
        }
    }

    private var resetToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                self.reset()
            } label: {
                HeaderToolbarIcon(symbol: ChatAppearance.Symbol.reset)
            }
            .disabled(self.viewModel.isStreaming)
            .accessibilityLabel(L10n.chatReset.string)
            .accessibilityIdentifier("chat.reset")
        }
    }

    // MARK: Notices

    @ViewBuilder
    private var bottomNotice: some View {
        if let notice = self.viewModel.notice, notice.edge == .bottom {
            self.noticeBar(notice.message)
                .padding(.bottom, self.appearance.spacing.units(2))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private var topNotice: some View {
        if let notice = self.viewModel.notice, notice.edge == .top {
            self.noticeBar(notice.message)
                .transition(.move(edge: .top))
        }
    }

    private func noticeBar(_ message: String) -> some View {
        NoticeBar(
            icon: ChatAppearance.Symbol.notice,
            message: message
        )
        .padding(.horizontal, self.appearance.spacing.units(4))
    }

    // MARK: Composer

    private var inputBar: some View {
        self.chatInput
            .background(alignment: .top) {
                // A permanent wrapper ensures the alignment guide is never dropped
                VStack {
                    self.bottomNotice
                }
                // Align the bottom of VStack to the top of the chatInput
                .alignmentGuide(.top) { $0[.bottom] }
            }
    }

    private var chatInput: some View {
        ChatInput(
            currentMessage: .init(
                get: { self.viewModel.currentMessage },
                set: { self.viewModel.currentMessage = $0 }
            ),
            pendingAttachments: .init(
                get: { self.viewModel.pendingAttachments },
                set: { self.viewModel.pendingAttachments = $0 }
            ),
            placeholder: self.viewModel.inputPlaceholder,
            leadingIcon: ChatAppearance.Symbol.privacy,
            showsAttachButton: self.viewModel.offersAttachments,
            canAttach: self.viewModel.canAttach,
            isEncodingAttachment: self.viewModel.isEncodingAttachment,
            onLeadingTap: { self.privacyDestination = .privacy },
            onAttach: { self.pickPhoto(for: .composer) },
            onSend: self.send,
            inputFocus: self.$inputFocused
        )
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding([.bottom, .top], self.appearance.spacing.units(3))
        .background {
            self.appearance.theme.background
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .contentShape(.rect)
        .geometryGroup()
    }
}
