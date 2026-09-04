//
//  PrivacyDataSheet.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-29.
//

import SwiftUI

/// The mutually-exclusive sheets reachable from the chat input's privacy control.
enum PrivacyDataDestination: Identifiable {
    case privacy
    case delete

    var id: Self { self }
}

/// Owns the privacy sheets' presentation — the exclusive A/B routing, the row actions, the
/// content-hugging height, and the drag indicator — so the presenting view stays free of it.
struct PrivacyDataSheetModifier: ViewModifier {

    @Binding var destination: PrivacyDataDestination?

    /// Opens the privacy policy, surfaced by the privacy sheet's row.
    let onOpenPrivacy: () -> Void

    /// The host's delete hook, surfaced by the delete sheet's confirm action.
    let onDeleteData: () async throws -> Void

    /// Shared across both sheets — only one is ever presented, so a single measured height serves.
    @State private var contentHeight: CGFloat?
    @State private var isLoading = false

    private var detents: Set<PresentationDetent> {
        if let contentHeight = self.contentHeight, contentHeight > 0 {
            [.height(contentHeight)]
        } else {
            [.medium]
        }
    }

    func body(content: Content) -> some View {
        content.sheet(item: self.$destination) { destination in
            self.sheet(for: destination)
                .modifier(LoadingOverlay(isLoading: self.isLoading))
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    self.contentHeight = height
                }
                .presentationDetents(self.detents)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func sheet(for destination: PrivacyDataDestination) -> some View {
        switch destination {
        case .privacy:
            PrivacyDataView(
                onPrivacy: self.onOpenPrivacy,
                onDelete: {
                    // Swap the presented sheet, dismiss privacy, present delete.
                    self.destination = .delete
                }
            )

        case .delete:
            DeleteDataView(onConfirm: {
                _ = Task {
                    self.isLoading = true
                    defer { self.isLoading = false }
                    // On failure the throw skips the dismiss and the Task discards the error;
                    // the host surfaces it. Success falls through and closes the sheet.
                    try await self.onDeleteData()
                    self.destination = nil
                }
            })
        }
    }
}
