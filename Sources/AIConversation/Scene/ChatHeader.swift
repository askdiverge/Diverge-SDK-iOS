//
//  ChatHeader.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-25.
//

import SwiftUI

/// The conversation's  header, rendering the configured subtitle.
struct ChatHeader: View {

    @Environment(\.appearance) private var appearance

    let subtitle: Subtitle

    var body: some View {
        Text(self.subtitle.attributedText)
            .font(self.appearance.font(size: 11))
            .foregroundStyle(self.appearance.theme.secondaryText)
            .tint(self.appearance.theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
