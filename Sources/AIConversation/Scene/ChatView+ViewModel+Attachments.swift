//
//  ChatView+ViewModel+Attachments.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Photo ingestion: composer picks and `request_image_upload` picks share one encode path.
extension ChatView.ViewModel {

    /// Encodes a picked photo into a pending attachment chip, dropping the oldest chip once
    /// ``maxPendingAttachments`` is reached. Failures surface as a bottom notice; the picker
    /// selection is cleared by the caller regardless.
    ///
    /// No filename is attached on purpose: `PhotosPickerItem` exposes only an asset identifier,
    /// which is neither a name nor something the backend should see. The API omits the caption
    /// when `filename` is absent, and the chip is labelled generically.
    func ingestPickedPhoto(_ data: Data) async {
        guard let pending = await self.encode(data, options: .message) else { return }
        self.pendingAttachments = Self.capped(self.pendingAttachments + [pending])
    }

    /// Encodes a pick routed from a `request_image_upload` marker — honours accepted MIME
    /// types (JPEG encode only) and the marker's decoded-byte cap.
    func ingestPromptPhoto(_ data: Data, marker: RequestImageUpload) async {
        guard marker.acceptedTypes.contains("image/jpeg") else {
            self.presentAttachmentFailure()
            return
        }
        let options = ImageAttachment.Options.message(maxDecodedBytes: marker.maxSizeBytes)
        guard let pending = await self.encode(data, options: options) else { return }
        self.pendingAttachments = Self.capped(self.pendingAttachments + [pending])
    }

    /// The one encode path for every photo destination: runs the injected encoder off the
    /// main actor, flags `isEncodingAttachment` meanwhile, and maps failures to notices.
    private func encode(_ data: Data, options: ImageAttachment.Options) async -> PendingAttachment? {
        self.isEncodingAttachment = true
        defer { self.isEncodingAttachment = false }

        do {
            let encoded = try await Task.detached(priority: .userInitiated) { [encode = self.encodeAttachment] in
                try await encode(data, options)
            }.value
            return PendingAttachment(
                thumbnail: Image(decorative: encoded.thumbnail, scale: 1),
                attachment: encoded.attachment,
                displayName: L10n.mediaImageLabel.string
            )
        } catch ImageAttachment.Failure.tooLarge {
            self.presentNotice(Notice(
                edge: .bottom,
                message: L10n.attachmentTooLarge.string,
                autoDismiss: .seconds(4)
            ))
            return nil
        } catch {
            self.presentAttachmentFailure()
            return nil
        }
    }

    /// Keeps the newest ``maxPendingAttachments`` entries.
    static func capped(_ attachments: [PendingAttachment]) -> [PendingAttachment] {
        Array(attachments.suffix(Self.maxPendingAttachments))
    }

    /// Surfaces a generic attachment-load failure from the view (picker / transferable miss).
    func presentAttachmentFailure() {
        self.presentNotice(Notice(
            edge: .bottom,
            message: L10n.attachmentFailed.string,
            autoDismiss: .seconds(4)
        ))
    }
}
