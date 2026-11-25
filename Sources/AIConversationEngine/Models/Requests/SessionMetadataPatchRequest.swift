//
//  SessionMetadataPatchRequest.swift
//  AIConversationEngine
//

import Foundation

/// Request body for `PATCH /api/v1/chat/session`, which merges host-supplied metadata into the
/// visitor's session. The backend deep-merges `metadata` into `session.metadata`, and verifies
/// `signedMetadata` against the chatbot's public key before merging its claims into
/// `session.verified_metadata`. Only the fields that are set are encoded.
package struct SessionMetadataPatchRequest: Encodable, Sendable, Equatable {

    /// Unsigned metadata from the device; downstream systems treat it as untrusted.
    package let metadata: [String: JSONValue]?

    /// An RS256 JWT the host's backend signed, sent as `signed_metadata`.
    package let signedMetadata: String?

    package init(metadata: [String: JSONValue]?, signedMetadata: String?) {
        self.metadata = metadata
        self.signedMetadata = signedMetadata
    }
}
