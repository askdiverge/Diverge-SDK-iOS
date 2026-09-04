//
//  NoticeBar.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI

/// A full-width bar showing an icon and a message.
struct NoticeBar: View {

    @Environment(\.appearance) private var appearance

    let icon: Image
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: self.appearance.spacing.units(3)) {
            self.icon
                .font(.system(size: 24))

            Text(self.message)
                .font(self.appearance.font(size: 15))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(self.appearance.theme.errorForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(self.appearance.spacing.units(4))
        .background(self.appearance.theme.errorBackground)
    }
}
