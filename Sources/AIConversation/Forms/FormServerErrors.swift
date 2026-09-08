//
//  FormServerErrors.swift
//  AIConversation
//

import Foundation
import AIConversationCore

/// Splits a 422 `error.params` list onto visible fields vs the card banner.
enum FormServerErrors {

    /// Last-wins per `field`. Keys that match a visible form field become `fieldErrors`;
    /// unmatched messages join a non-empty envelope `message` on `formError`.
    static func apply(
        params: [ValidationError],
        formMessage: String?,
        knownFieldKeys: Set<String>
    ) -> (fieldErrors: [String: String], formError: String?) {
        let byField = Dictionary(
            params.map { ($0.field, $0.message) },
            uniquingKeysWith: { _, last in last }
        )

        var fieldErrors: [String: String] = [:]
        var leftover: [String] = []
        var leftoverKeys = Set<String>()

        for param in params {
            if knownFieldKeys.contains(param.field) {
                continue
            }
            guard leftoverKeys.insert(param.field).inserted else { continue }
            leftover.append(byField[param.field] ?? param.message)
        }

        for (field, message) in byField where knownFieldKeys.contains(field) {
            fieldErrors[field] = message
        }

        var banners: [String] = []
        let envelope = formMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !envelope.isEmpty {
            banners.append(envelope)
        }
        for message in leftover {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                banners.append(trimmed)
            }
        }

        return (fieldErrors, banners.isEmpty ? nil : banners.joined(separator: "\n"))
    }
}
