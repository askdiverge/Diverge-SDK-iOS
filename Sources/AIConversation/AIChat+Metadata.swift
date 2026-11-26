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
    /// merged metadata is limited to 32 KiB.
    ///
    /// Returns at once on the main actor and can be called at any time, before the chat is shown
    /// too. Calls are sent in order while a chat of this `AIChat` is on screen with a session.
    /// Those made while none is wait, merged into one patch, for the next chat shown. The backend
    /// refuses a patch over 32 KiB, alone or merged with what the session already holds, and the
    /// patch is dropped with every call merged into it. Metadata comes from the device, so
    /// systems that read it treat it as untrusted.
    ///
    /// - Parameter metadata: Values to merge, such as the store, language or screen the visitor
    ///   is on. They nest at most 20 levels deep, the dictionary's own values being the first,
    ///   use neither a reserved top-level key (`verified_metadata`, `signed_metadata`) nor the key
    ///   `__proto__`, `prototype` or `constructor` at any depth, and hold finite numbers only, as
    ///   the backend requires of every patch. A call outside those rules, or with an empty
    ///   dictionary, does nothing.
    func setMetadata(_ metadata: [String: MetadataValue]) {
        guard !metadata.isEmpty, MetadataValue.accepts(metadata) else { return }
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

    /// Whether `metadata` keeps to the backend's rules for a patch, its 32 KiB limit aside: no
    /// reserved top-level key, and every value within the depth limit, with finite numbers and no
    /// blocked key.
    static func accepts(_ metadata: [String: Self]) -> Bool {
        metadata.keys.allSatisfy { !Self.reservedKeys.contains($0) }
            && Self.object(metadata).isAccepted(atDepth: 0)
    }
}

// MARK: - Backend rules

private extension AIChat.MetadataValue {

    /// The deepest level the backend takes a value at; the top-level dictionary is level 0.
    static let maximumDepth = 20

    /// Keys the backend refuses at any depth.
    static let blockedKeys: Set<String> = ["__proto__", "prototype", "constructor"]

    /// Top-level keys the backend keeps for verified metadata.
    static let reservedKeys: Set<String> = ["verified_metadata", "signed_metadata"]

    /// Whether the backend takes this value at `depth`: no deeper than ``maximumDepth``, with
    /// finite numbers, which JSON requires, and no blocked key. The check stops at the limit, so
    /// it stays shallow however deep the value goes.
    func isAccepted(atDepth depth: Int) -> Bool {
        guard depth <= Self.maximumDepth else { return false }
        return switch self {
        case .double(let value): value.isFinite
        case .array(let values): values.allSatisfy { $0.isAccepted(atDepth: depth + 1) }
        case .object(let values):
            values.allSatisfy { key, value in
                !Self.blockedKeys.contains(key) && value.isAccepted(atDepth: depth + 1)
            }
        case .string, .int, .bool, .null: true
        }
    }
}
