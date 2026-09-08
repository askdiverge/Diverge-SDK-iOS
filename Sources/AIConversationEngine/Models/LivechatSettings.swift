//
//  LivechatSettings.swift
//  AIConversationEngine
//

import Foundation

/// Livechat block from `GET /api/v1/chat/config`.
/// [API ref](https://docs.dialoge.ai/api#model/livechat-config)
package struct LivechatSettings: Decodable, Sendable, Equatable {

    /// Whether the visitor can request a human agent right now.
    package let enabled: Bool
    /// Whether livechat is configured for this chatbot at all.
    package let configured: Bool
    package let availabilityStatus: AvailabilityStatus
    package let availabilityReason: AvailabilityReason
    /// Whether the header livechat control should render when idle.
    package let showLivechatLogo: Bool
    /// Whether participants may send attachments during an active session.
    package let attachmentsEnabled: Bool
    /// Max attachment size in decoded bytes for an active-session upload.
    package let maxAttachmentSizeBytes: Int

    package init(
        enabled: Bool = false,
        configured: Bool = false,
        availabilityStatus: AvailabilityStatus = .offline,
        availabilityReason: AvailabilityReason = .disabled,
        showLivechatLogo: Bool = true,
        attachmentsEnabled: Bool = false,
        maxAttachmentSizeBytes: Int = 5_242_880
    ) {
        self.enabled = enabled
        self.configured = configured
        self.availabilityStatus = availabilityStatus
        self.availabilityReason = availabilityReason
        self.showLivechatLogo = showLivechatLogo
        self.attachmentsEnabled = attachmentsEnabled
        self.maxAttachmentSizeBytes = maxAttachmentSizeBytes
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.configured = try container.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        self.availabilityStatus =
            try container.decodeIfPresent(AvailabilityStatus.self, forKey: .availabilityStatus) ?? .offline
        self.availabilityReason =
            try container.decodeIfPresent(AvailabilityReason.self, forKey: .availabilityReason) ?? .disabled
        self.showLivechatLogo = try container.decodeIfPresent(Bool.self, forKey: .showLivechatLogo) ?? true
        self.attachmentsEnabled = try container.decodeIfPresent(Bool.self, forKey: .attachmentsEnabled) ?? false
        self.maxAttachmentSizeBytes =
            try container.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeBytes) ?? 5_242_880
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, configured, availabilityStatus, availabilityReason
        case showLivechatLogo, attachmentsEnabled, maxAttachmentSizeBytes
    }

    /// [API ref](https://docs.dialoge.ai/api#model/livechat-availability-status)
    package enum AvailabilityStatus: String, ExtendableEnum, Sendable {
        case live, offline, unknown
    }

    /// [API ref](https://docs.dialoge.ai/api#model/livechat-availability-reason)
    package enum AvailabilityReason: String, ExtendableEnum, Sendable {
        case disabled
        case manualLive = "manual_live"
        case manualOffline = "manual_offline"
        case alwaysOn = "always_on"
        case withinWorkingHours = "within_working_hours"
        case outsideWorkingHours = "outside_working_hours"
        case unknown
    }

    /// Livechat is on and currently accepting handovers.
    package var isAvailable: Bool {
        self.enabled && self.availabilityStatus == .live
    }
}
