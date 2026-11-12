//
//  ChatView+ViewModel+Attachments.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

extension ChatView.ViewModel {

    /// Cap on composer chips so a long pick session cannot grow without bound.
    static let maxPendingAttachments = 8

    /// Whether the host offers photo attachments at all.
    var offersAttachments: Bool {
        self.attachments == .photoLibrary
    }

    /// Whether a reply is currently streaming.
    var isStreaming: Bool {
        self.snapshot?.streamingTurnID != nil
    }

    /// The one enable rule for every "add a photo" entry point (composer button, upload-prompt
    /// card): attachments offered, nothing encoding, nothing streaming.
    var canAttach: Bool {
        self.offersAttachments && !self.isEncodingAttachment && !self.isStreaming
    }

    /// Composer attach while livechat is active also requires the server's
    /// ``LivechatConfig/attachmentsEnabled`` flag.
    var canAttachConsideringLivechat: Bool {
        guard self.canAttach else { return false }
        if self.livechatStatus == .active {
            return self.livechatConfig.attachmentsEnabled
        }
        return true
    }

    /// Puts a failed send's text and chips back in the composer, ahead of any picked meanwhile.
    /// The cap limits picking, so a restore keeps every photo the visitor chose.
    func restoreDraft(text: String, attachments: [PendingAttachment]) {
        self.currentMessage = text
        self.pendingAttachments = attachments + self.pendingAttachments
    }

    /// Encodes a picked photo into a pending attachment chip, dropping the oldest chip once
    /// ``maxPendingAttachments`` is reached.
    func ingestPickedPhoto(_ data: Data) async {
        let livechatDecoded: Int? =
            self.livechatConfig.attachmentsEnabled
                && (self.livechatStatus == .waiting || self.livechatStatus == .active)
            ? self.livechatConfig.maxAttachmentSizeBytes
            : nil
        let options = ImageAttachment.Options.message(maxDecodedBytes: livechatDecoded)
        guard let pending = await self.encode(data, options: options) else { return }
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

    /// Encodes a picked photo for a form file field or a ticket attachment.
    func ingestFormPhoto(
        _ data: Data,
        maxBytes: Int,
        filename: String
    ) async -> PendingAttachment? {
        let options = ImageAttachment.Options.action(filename: filename, maxDecodedBytes: maxBytes)
        return await self.encode(data, options: options)
    }

    /// Holds the attach and send controls for as long as `work` runs — from loading the pick
    /// out of the library through its encode — so a send waits for the photo it is meant for.
    func preparingAttachment(_ work: () async -> Void) async {
        self.preparingAttachments += 1
        defer { self.finishPreparingAttachment() }
        await work()
    }

    /// The one encode path for every composer / prompt / form photo destination.
    func encode(_ data: Data, options: ImageAttachment.Options) async -> PendingAttachment? {
        self.preparingAttachments += 1
        defer { self.finishPreparingAttachment() }

        do {
            let encoded = try await Task.detached(priority: .userInitiated) { [encode = self.encodeAttachment] in
                try await encode(data, options)
            }.value
            guard !self.discardsPreparedAttachment else { return nil }
            return PendingAttachment(
                thumbnail: Image(decorative: encoded.thumbnail, scale: 1),
                attachment: encoded.attachment,
                displayName: options.filename ?? L10n.mediaImageLabel.string
            )
        } catch ImageAttachment.Failure.tooLarge {
            self.present(Notice(
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

    private func finishPreparingAttachment() {
        self.preparingAttachments -= 1
        if self.preparingAttachments == 0 {
            self.discardsPreparedAttachment = false
        }
    }

    /// Surfaces a generic attachment-load failure from the view (picker / transferable miss).
    func presentAttachmentFailure() {
        self.present(Notice(
            edge: .bottom,
            message: L10n.attachmentFailed.string,
            autoDismiss: .seconds(4)
        ))
    }

    /// Clears composer chips when a livechat session that forbids attachments becomes active.
    func dropPendingAttachmentsForLivechat() {
        guard !self.pendingAttachments.isEmpty else { return }
        self.pendingAttachments = []
        self.present(Notice(
            edge: .bottom,
            message: L10n.livechatAttachmentsDropped.string,
            autoDismiss: .seconds(4)
        ))
    }

    /// Keeps the newest ``maxPendingAttachments`` entries.
    private static func capped(_ attachments: [PendingAttachment]) -> [PendingAttachment] {
        Array(attachments.suffix(Self.maxPendingAttachments))
    }
}
