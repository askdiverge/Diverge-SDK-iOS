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
    static let inputSend = string("input.send")

    /// Toolbar close / reset button accessibility labels.
    static let chatClose = string("chat.close")
    static let chatReset = string("chat.reset")

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
