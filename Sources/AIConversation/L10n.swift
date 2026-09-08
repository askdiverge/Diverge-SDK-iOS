//
//  L10n.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-05.
//

import Foundation

/// The chat's user-facing copy, resolved from the module's String Catalog (`Localizable.xcstrings`).
/// Keys are opaque identifiers — a missing catalog entry surfaces the key itself
enum L10n {

    static let inputPlaceholder = string("input.placeholder")
    static let inputAttachPhoto = string("input.attachPhoto")

    static let attachmentRemove = string("attachment.remove")
    static let attachmentTooLarge = string("attachment.tooLarge")
    static let attachmentFailed = string("attachment.failed")

    static let sessionEndedTitle = string("session.ended.title")
    static let sessionEndedMessage = string("session.ended.message")
    static let sessionEndedDismiss = string("session.ended.dismiss")

    static let errorTitle = string("error.title")
    static let errorMessage = string("error.message")
    static let errorRetry = string("error.retry")

    static let noticeBusy = string("notice.busy")
    static let noticeSendFailed = string("notice.sendFailed")

    static let historyLoading = string("history.loading")
    static let historyLoadFailed = string("history.loadFailed")

    static let suggestionSendHint = string("suggestion.sendHint")
    static let startPromptSendHint = string("startPrompt.sendHint")

    static let productOpen = string("product.open")
    static let productOpenHint = string("product.openHint")
    static let productAddToCart = string("product.addToCart")
    static let productAddToCartHint = string("product.addToCartHint")

    static let imageUploadPrompt = string("imageUpload.prompt")
    static let imageUploadAddPhoto = string("imageUpload.addPhoto")
    static let imageUploadHint = string("imageUpload.hint")

    static let livechatTalkToPerson = string("livechat.talkToPerson")
    static let livechatHumanAgentPrompt = string("livechat.humanAgentPrompt")
    static let livechatHumanAgentHint = string("livechat.humanAgentHint")
    static let livechatOffline = string("livechat.offline")
    static let livechatQueuedNote = string("livechat.queuedNote")
    static let livechatEndedNote = string("livechat.endedNote")
    static let livechatLeaveConfirmTitle = string("livechat.leaveConfirmTitle")
    static let livechatLeaveConfirmMessage = string("livechat.leaveConfirmMessage")
    static let livechatLeaveConfirmAction = string("livechat.leaveConfirmAction")
    static let livechatWaitingPlaceholder = string("livechat.waitingPlaceholder")
    static let livechatAgentTyping = string("livechat.agentTyping")
    static let livechatToolbarRequest = string("livechat.toolbarRequest")
    static let livechatToolbarLeave = string("livechat.toolbarLeave")
    static let livechatAgentFallback = string("livechat.agentFallback")
    static let livechatA11yAvailable = string("livechat.a11yAvailable")
    static let livechatA11yOffline = string("livechat.a11yOffline")
    static let livechatAttachmentsDropped = string("livechat.attachmentsDropped")

    /// "Message {name}…"
    static func livechatAgentPlaceholder(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "livechat.agentPlaceholder",
            defaultValue: "Message \(name)…",
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// "{name} joined the chat"
    static func livechatAgentJoinedNote(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "livechat.agentJoinedNote",
            defaultValue: "\(name) joined the chat",
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    /// "{name} is typing…"
    static func livechatAgentTypingNamed(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "livechat.agentTypingNamed",
            defaultValue: "\(name) is typing…",
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    static let formContactTitle = string("form.contactTitle")
    static let formTicketTitle = string("form.ticketTitle")
    static let formSubmit = string("form.submit")
    static let formSubmitting = string("form.submitting")
    static let formRequired = string("form.required")
    static let formInvalidEmail = string("form.invalidEmail")
    static let formSubmitFailed = string("form.submitFailed")
    static let formSubmittedDefault = string("form.submittedDefault")
    static let formAddPhoto = string("form.addPhoto")
    static let formRemovePhoto = string("form.removePhoto")
    static let formAttachmentsDisabled = string("form.attachmentsDisabled")
    static let formReadOnly = string("form.readOnly")
    static let formAccessibilityHint = string("form.accessibilityHint")
    static let formSelectOption = string("form.selectOption")
    static let formDone = string("form.done")

    static let sessionFormTitle = string("sessionForm.title")
    static let sessionFormDescription = string("sessionForm.description")
    static let sessionFormSave = string("sessionForm.save")
    static let sessionFormSaving = string("sessionForm.saving")
    static let sessionFormSaved = string("sessionForm.saved")
    static let sessionFormFailed = string("sessionForm.failed")

    static let ratingTitle = string("rating.title")
    static let ratingMessage = string("rating.message")
    static let ratingSkip = string("rating.skip")
    static let ratingSkipHint = string("rating.skipHint")
    static let ratingSkipFeedbackHint = string("rating.skipFeedbackHint")
    static let ratingFeedbackTitle = string("rating.feedbackTitle")
    static let ratingFeedbackPlaceholder = string("rating.feedbackPlaceholder")
    static let ratingFeedbackSubmit = string("rating.feedbackSubmit")
    static let ratingFailed = string("rating.failed")
    static let ratingClose = string("rating.close")
    static let ratingScore1 = string("rating.score.1")
    static let ratingScore2 = string("rating.score.2")
    static let ratingScore3 = string("rating.score.3")
    static let ratingScore4 = string("rating.score.4")
    static let ratingScore5 = string("rating.score.5")

    /// Parameterised and pluralised in the catalog — "Fill in at least %lld field(s)".
    static func formMinFilled(_ count: Int) -> LocalizedStringResource {
        LocalizedStringResource(
            "form.minFilled",
            defaultValue: "Fill in at least \(count) fields",
            bundle: .atURL(Bundle.module.bundleURL)
        )
    }

    static let mediaImageLabel = string("media.imageLabel")
    static let mediaOpenHint = string("media.openHint")
    static let mediaUnavailable = string("media.unavailable")

    static let privacyTitle = string("privacy.title")
    static let privacyPolicy = string("privacy.policy")
    static let privacyDownloadEntry = string("privacy.downloadEntry")
    static let privacyDownloadError = string("privacy.downloadError")
    static let privacyDeleteEntry = string("privacy.deleteEntry")

    static let bannerDismiss = string("banner.dismiss")
    static let bannerCTA = string("banner.cta")

    static let deleteTitle = string("delete.title")
    static let deleteMessage = string("delete.message")
    static let deleteConfirmation = string("delete.confirmation")
    static let deleteValidation = string("delete.validation")
    static let deleteCancel = string("delete.cancel")
    static let deleteConfirm = string("delete.confirm")

    private static func string(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}

extension LocalizedStringResource {

    /// The resolved string, for APIs that take a plain `String` instead of a resource.
    var string: String { String(localized: self) }
}
