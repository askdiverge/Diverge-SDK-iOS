//
//  LoadingOverlay.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-13.
//

import SwiftUI

/// Dims the modified view and centres a spinner while `isLoading`, blocking interaction beneath.
struct LoadingOverlay: ViewModifier {

    @Environment(\.appearance) private var appearance

    let isLoading: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if self.isLoading {
                ProgressView()
                    .tint(self.appearance.theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appearance.theme.background.opacity(0.4))
            }
        }
    }
}
