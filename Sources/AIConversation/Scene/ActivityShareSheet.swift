//
//  ActivityShareSheet.swift
//  AIConversation
//

import SwiftUI

#if os(iOS)
import UIKit

/// System share sheet for the GDPR export JSON.
///
/// On iPad, `UIActivityViewController` must have a popover source — we pin it
/// to this controller's own view (the SwiftUI `.sheet` host).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: self.onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: self.items,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.onComplete?()
        }
        Self.anchorPopover(of: controller)
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        context.coordinator.onComplete = self.onComplete
        Self.anchorPopover(of: controller)
    }

    private static func anchorPopover(of controller: UIActivityViewController) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = controller.view
        let bounds = controller.view.bounds
        popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
    }

    final class Coordinator {
        var onComplete: (() -> Void)?
        init(onComplete: (() -> Void)?) {
            self.onComplete = onComplete
        }
    }
}

#elseif os(macOS)
import AppKit

/// Best-effort macOS sharing picker. The iOS Sample is the supported host;
/// Harness share is not a product surface.
struct ActivityShareSheet: NSViewRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(items: self.items, onComplete: self.onComplete)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.items = self.items
        context.coordinator.onComplete = self.onComplete
        guard !context.coordinator.didShow else { return }
        context.coordinator.didShow = true
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            let picker = NSSharingServicePicker(items: context.coordinator.items)
            picker.delegate = context.coordinator
            context.coordinator.picker = picker
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var items: [Any]
        var onComplete: (() -> Void)?
        var didShow = false
        var picker: NSSharingServicePicker?

        init(items: [Any], onComplete: (() -> Void)?) {
            self.items = items
            self.onComplete = onComplete
        }

        func sharingServicePicker(
            _ sharingServicePicker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            self.onComplete?()
        }
    }
}
#endif

/// Identifiable wrapper so a temp export file can drive `.sheet(item:)`.
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}
