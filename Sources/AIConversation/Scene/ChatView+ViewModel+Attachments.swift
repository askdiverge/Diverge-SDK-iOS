//
//  ChatView+ViewModel+Attachments.swift
//  AIConversation
//

import Foundation
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

    /// Puts a failed send's text and chips back in the composer.
    func restoreDraft(text: String, attachments: [PendingAttachment]) {
        self.currentMessage = text
        self.pendingAttachments = Self.capped(attachments + self.pendingAttachments)
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

    /// Keeps the newest ``maxPendingAttachments`` entries.
    private static func capped(_ attachments: [PendingAttachment]) -> [PendingAttachment] {
        Array(attachments.suffix(Self.maxPendingAttachments))
    }
}
