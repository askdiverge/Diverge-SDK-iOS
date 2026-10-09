//
//  LivechatConfig.swift
//  AIConversationEngine
//

import Foundation

/// Livechat block from `GET /api/v1/chat/config`.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatconfig)
package struct LivechatConfig: Decodable, Sendable, Equatable {

    /// The config with every field at its server default, as a deployment without a livechat
    /// block describes it. Decoding fills an absent field from here too.
    package static let serverDefaults = LivechatConfig(
        enabled: false,
        configured: false,
        availabilityStatus: .offline,
        availabilityReason: .disabled,
        showLivechatLogo: true,
        attachmentsEnabled: false,
        maxAttachmentSizeBytes: 5_242_880
    )

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

    private init(
        enabled: Bool,
        configured: Bool,
        availabilityStatus: AvailabilityStatus,
        availabilityReason: AvailabilityReason,
        showLivechatLogo: Bool,
        attachmentsEnabled: Bool,
        maxAttachmentSizeBytes: Int
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
        let defaults = Self.serverDefaults
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        self.configured = try container.decodeIfPresent(Bool.self, forKey: .configured) ?? defaults.configured
        self.availabilityStatus = try container.decodeIfPresent(AvailabilityStatus.self, forKey: .availabilityStatus)
            ?? defaults.availabilityStatus
        self.availabilityReason = try container.decodeIfPresent(AvailabilityReason.self, forKey: .availabilityReason)
            ?? defaults.availabilityReason
        self.showLivechatLogo = try container.decodeIfPresent(Bool.self, forKey: .showLivechatLogo)
            ?? defaults.showLivechatLogo
        self.attachmentsEnabled = try container.decodeIfPresent(Bool.self, forKey: .attachmentsEnabled)
            ?? defaults.attachmentsEnabled
        self.maxAttachmentSizeBytes = try container.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeBytes)
            ?? defaults.maxAttachmentSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, configured, availabilityStatus, availabilityReason
        case showLivechatLogo, attachmentsEnabled, maxAttachmentSizeBytes
    }

    /// Whether a visitor can hand over to a live agent right now. The backend decides it from the
    /// chatbot's livechat settings, working hours and manual overrides; the client offers the
    /// handover control only while it is `live`. A case is added when the backend introduces a
    /// new availability state.
    /// [API ref](https://docs.askdiverge.ai/api#model/livechatavailabilitystatus)
    package enum AvailabilityStatus: String, ExtendableEnum, Sendable {
        case live, offline, unknown
    }

    /// Why the backend set ``AvailabilityStatus``: livechat switched off (`disabled`), an operator
    /// override (`manual_live` / `manual_offline`), a chatbot with no working hours
    /// (`always_on`), or its working-hours schedule (`within_working_hours` /
    /// `outside_working_hours`). The client picks its unavailable copy from it. A case is added
    /// when the backend gains a new reason.
    /// [API ref](https://docs.askdiverge.ai/api#model/livechatavailabilityreason)
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
