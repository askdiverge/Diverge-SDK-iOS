//
//  DismissKeyboardOnTap.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-19.
//

import SwiftUI

/// While active, overlays a clear layer that claims a tap or drag to dismiss the keyboard — so the tap
/// can't fire a link in the content beneath, and the drag can't fall through to the sheet's
/// pull-to-dismiss. Claiming the drag is the point: an unclaimed drag reads as pull-to-dismiss.
struct DismissKeyboardOnTap: ViewModifier {

    let isActive: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if self.isActive {
                Color.clear
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in self.onDismiss() }
                    )
            }
        }
    }
}
