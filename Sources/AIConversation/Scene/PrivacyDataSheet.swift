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
///
/// The share sheet is nested **on this sheet**, not on `ChatView` (a second `sheet` on ChatView
/// never surfaces when Sample already presents ChatView in a host sheet).
struct PrivacyDataSheetModifier: ViewModifier {

    @Binding var destination: PrivacyDataDestination?

    /// Opens the privacy policy, surfaced by the privacy sheet's row.
    let onOpenPrivacy: () -> Void

    /// Fetches the GDPR export and returns a local file URL for the share sheet.
    let onExportData: () async throws -> URL

    /// Removes the temp export file (PII). Called when Privacy dismisses or share completes.
    let onDiscardExport: () -> Void

    /// The host's delete hook, surfaced by the delete sheet's confirm action.
    let onDeleteData: () async throws -> Void

    /// Fired when export hits a 401 so the chat can show the session-ended alert.
    let onSessionEnded: () -> Void

    /// Shared across both sheets — only one is ever presented, so a single measured height serves.
    @State private var contentHeight: CGFloat?
    @State private var isLoading = false
    @State private var exportError: String?
    @State private var shareFile: ShareFile?
    @State private var exportLifecycle = PrivacyExportLifecycle()

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
                .sheet(item: self.$shareFile) { file in
                    ActivityShareSheet(items: [file.url], onComplete: self.finishShare)
                }
                .onDisappear {
                    self.abandonExport()
                }
        }
    }

    @ViewBuilder
    private func sheet(for destination: PrivacyDataDestination) -> some View {
        switch destination {
        case .privacy:
            PrivacyDataView(
                onPrivacy: self.onOpenPrivacy,
                onDownload: { self.export() },
                onDelete: {
                    self.exportError = nil
                    self.destination = .delete
                },
                exportError: self.exportError
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

    private func export() {
        self.exportError = nil
        self.exportLifecycle.start {
            self.isLoading = true
            defer { self.isLoading = false }
            do {
                let url = try await self.onExportData()
                guard let file = self.exportLifecycle.shareFileIfActive(url: url) else { return }
                self.shareFile = file
            } catch is ChatView.SessionEnded {
                guard self.exportLifecycle.isActive else { return }
                self.destination = nil
                self.onSessionEnded()
            } catch {
                guard self.exportLifecycle.isActive else { return }
                self.exportError = L10n.privacyDownloadError.string
            }
        }
    }

    private func finishShare() {
        self.shareFile = nil
        self.onDiscardExport()
    }

    private func abandonExport() {
        self.exportLifecycle.cancel()
        self.exportError = nil
        self.shareFile = nil
        self.isLoading = false
        self.onDiscardExport()
    }
}
