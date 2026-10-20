//
//  FormServerErrors.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Splits a 422 `error.params` list onto visible fields vs the card banner.
enum FormServerErrors {

    /// A `field` path that names a visible form field puts the SDK's localized "check this field"
    /// copy under that field. Anything else — an unmatched path, or a rejection with no params —
    /// shows the SDK's localized send-failed copy on the banner. The backend's English messages,
    /// per param and on the envelope, are never shown.
    static func apply(
        params: [ValidationError],
        knownFieldKeys: Set<String>
    ) -> (fieldErrors: [String: String], formError: String?) {
        var fieldErrors: [String: String] = [:]
        var hasUnmatched = params.isEmpty
        for param in params {
            let key = Self.fieldKey(param.field)
            if knownFieldKeys.contains(key) {
                fieldErrors[key] = L10n.formFieldRejected.string
            } else {
                hasUnmatched = true
            }
        }
        return (fieldErrors, hasUnmatched ? L10n.formSubmitFailed.string : nil)
    }

    /// The form field a server `field` path names. The API reports body paths:
    /// `action.fields.email` (contact form), `action.values.email` / `action.files.photo` (custom
    /// form), `action.email` (support ticket) and `values.email` (waiting-form PATCH) all name
    /// their last segment.
    static func fieldKey(_ path: String) -> String {
        let prefixes = ["action.fields.", "action.values.", "action.files.", "action.", "values."]
        for prefix in prefixes where path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }
}
