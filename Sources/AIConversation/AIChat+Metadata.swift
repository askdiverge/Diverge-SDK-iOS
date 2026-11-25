//
//  AIChat+Metadata.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

public extension AIChat {

    /// Merges `metadata` into the visitor's chat session, where the backend, handover webhooks and
    /// Universal API variables read it as `session.metadata`. Repeated calls deep-merge: nested
    /// objects merge, any other value replaces the earlier one, and a key stays once set. The
    /// merged metadata is limited to 32 KiB and 20 levels. The backend refuses a patch that uses
    /// a reserved top-level key (`verified_metadata`, `signed_metadata`) or, at any depth, the key
    /// `__proto__`, `prototype` or `constructor`.
    ///
    /// Returns at once on the main actor and can be called at any time, before the chat is shown
    /// too. Calls are sent in order while a chat of this `AIChat` is on screen with a session.
    /// Those made while none is wait, merged into one patch, for the next chat shown. Metadata the
    /// backend refuses is dropped. It comes from the device, so systems that read it treat it as
    /// untrusted.
    ///
    /// - Parameter metadata: Values to merge, such as the store, language or screen the visitor
    ///   is on. An empty dictionary does nothing.
    func setMetadata(_ metadata: [String: MetadataValue]) {
        guard !metadata.isEmpty else { return }
        self.sessionMetadata.enqueue(.init(
            metadata: metadata.mapValues(\.jsonValue),
            signedMetadata: nil
        ))
    }

    /// Sends a token the host's backend signed, so the backend can verify it against the
    /// chatbot's public key and merge its claims into the session as `session.verified_metadata`.
    /// Claims the chatbot names secret are kept apart for the actions that use them.
    ///
    /// Returns at once on the main actor and can be called at any time, before the chat is shown
    /// too. A token is sent while a chat of this `AIChat` is on screen with a session. While none
    /// is, the newest token waits for the next chat shown, and replaces one set before it. A token
    /// the backend refuses (a bad signature, expired by the time it arrives, too long-lived, or a
    /// chatbot with no public key) is dropped; sign a new one and call again. The verified claims
    /// are used only while the newest token is unexpired, so call again as you present the chat and
    /// before the token expires while the chat is open.
    ///
    /// - Parameter token: An RS256 JWT with `iat` and `exp` at most 15 minutes apart. A blank
    ///   string does nothing.
    func setSignedMetadata(_ token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        self.sessionMetadata.enqueue(.init(metadata: nil, signedMetadata: token))
    }

    /// A JSON value for ``setMetadata(_:)``. Literals and interpolated strings convert directly:
    /// `["storeSlug": "boozt-se", "screen": "product/\(id)", "cart": ["items": 2]]`. JSON `null`
    /// is written ``null``.
    enum MetadataValue: Sendable, Hashable {
        /// A JSON string.
        case string(String)
        /// A JSON number without a fraction.
        case int(Int)
        /// A JSON number with a fraction.
        case double(Double)
        /// A JSON `true` or `false`.
        case bool(Bool)
        /// A JSON array; it replaces an earlier array as a whole.
        case array([MetadataValue])
        /// A JSON object; the backend merges it into an earlier object under the same key.
        case object([String: MetadataValue])
        /// A JSON `null`; it replaces an earlier value, and the key stays.
        case null
    }
}

extension AIChat.MetadataValue: ExpressibleByStringInterpolation {
    /// A string literal, plain or interpolated.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension AIChat.MetadataValue: ExpressibleByIntegerLiteral {
    /// An integer literal.
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension AIChat.MetadataValue: ExpressibleByFloatLiteral {
    /// A floating-point literal.
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension AIChat.MetadataValue: ExpressibleByBooleanLiteral {
    /// A Boolean literal.
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension AIChat.MetadataValue: ExpressibleByArrayLiteral {
    /// An array literal.
    public init(arrayLiteral elements: AIChat.MetadataValue...) {
        self = .array(elements)
    }
}

extension AIChat.MetadataValue: ExpressibleByDictionaryLiteral {
    /// A dictionary literal; a repeated key keeps its last value.
    public init(dictionaryLiteral elements: (String, AIChat.MetadataValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension AIChat.MetadataValue {

    /// The wire form of this value.
    var jsonValue: JSONValue {
        switch self {
        case .string(let value): .string(value)
        case .int(let value): .int(value)
        case .double(let value): .double(value)
        case .bool(let value): .bool(value)
        case .array(let values): .array(values.map(\.jsonValue))
        case .object(let values): .object(values.mapValues(\.jsonValue))
        case .null: .null
        }
    }
}
