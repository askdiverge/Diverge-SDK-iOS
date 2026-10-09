//
//  LivechatControlButton.swift
//  AIConversation
//

import SwiftUI

/// The header control that asks for a person, or ends the session; accent during a session, and
/// dimmed while livechat is offline. Its accessibility value says whether the visitor is queued or
/// connected.
struct LivechatControlButton: View {

    @Environment(\.appearance) private var appearance

    let viewModel: ChatView.ViewModel

    var body: some View {
        Button {
            Task { await self.viewModel.toggleLivechat() }
        } label: {
            ChatAppearance.Symbol.livechat
        }
        .tint(self.tint)
        .help(self.label)
        .accessibilityLabel(self.label)
        .accessibilityValue(self.statusValue)
        .accessibilityIdentifier("livechat.control")
        .disabled(self.viewModel.isLivechatBusy)
    }
}

private extension LivechatControlButton {

    var tint: Color? {
        if self.viewModel.livechatStatus.isInSession { return self.appearance.theme.accent }
        return self.viewModel.livechatControl == .offline ? self.appearance.theme.secondaryText : nil
    }

    var label: Text {
        switch self.viewModel.livechatControl {
        case .end: Text(L10n.livechatEnd)
        case .offline: Text(L10n.livechatOffline)
        case .start, .hidden: Text(L10n.livechatStart)
        }
    }

    var statusValue: Text {
        switch self.viewModel.livechatStatus {
        case .waiting: Text(L10n.livechatWaitingStatus)
        case .active: Text(L10n.livechatActiveStatus)
        case .inactive, .closed, .unknown: Text(verbatim: "")
        }
    }
}
