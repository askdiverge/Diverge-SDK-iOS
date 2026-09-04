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

    static let sessionEndedTitle = string("session.ended.title")
    static let sessionEndedMessage = string("session.ended.message")
    static let sessionEndedDismiss = string("session.ended.dismiss")

    static let errorTitle = string("error.title")
    static let errorMessage = string("error.message")
    static let errorRetry = string("error.retry")

    static let noticeBusy = string("notice.busy")
    static let noticeHistoryLoadFailed = string("notice.historyLoadFailed")
    static let noticeSendFailed = string("notice.sendFailed")

    static let privacyTitle = string("privacy.title")
    static let privacyPolicy = string("privacy.policy")
    static let privacyDeleteEntry = string("privacy.deleteEntry")

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
