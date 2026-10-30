//
//  ChatView+ViewModel+Dependencies.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

extension ChatView.ViewModel {

    /// What the view model calls beyond the provider. ``live(service:)`` is the real set, and a
    /// test replaces the members it scripts.
    struct Dependencies {
        var encodeAttachment: AttachmentEncoder
        var submitAction: ActionSubmitter
        var fetchForm: FormFetcher
        var fetchSession: WaitingFormController.SessionFetcher
        var patchFormValues: WaitingFormController.ValuesPatcher
        var submitLivechatFeedback: LivechatRatingController.Submitter
        var rateConversation: ConversationRatingController.Submitter
        var livechat: LivechatSession

        /// Encodes on the device and goes over the wire through `service`.
        static func live(service: ChatService) -> Dependencies {
            Dependencies(
                encodeAttachment: { data, options async throws(ImageAttachment.Failure) in
                    try ImageAttachment.encode(data, options: options)
                },
                submitAction: { try await service.submitAction($0) },
                fetchForm: { try await service.fetchForm(id: $0) },
                fetchSession: { try await service.fetchSession() },
                patchFormValues: { try await service.patchFormValues(formId: $0, values: $1) },
                submitLivechatFeedback: { try await service.submitLivechatFeedback($0) },
                rateConversation: { try await service.rateConversation($0) },
                livechat: LivechatSession(service: service)
            )
        }
    }
}
