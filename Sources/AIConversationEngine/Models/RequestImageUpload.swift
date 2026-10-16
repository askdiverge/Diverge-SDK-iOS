//
//  RequestImageUpload.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to prompt the visitor to upload an image. Carries accepted MIME types
/// and a size limit inline; the SDK owns all copy (the API supplies none).
///
/// Arrives only as a full `part` / history / `done` — markers never stream via `part_delta`.
/// A marker missing a field decodes as `.unknown` upstream.
/// [API ref](https://docs.askdiverge.ai/api#model/requestimageuploadmarker)
package struct RequestImageUpload: Decodable, Sendable, Equatable {

    /// Stable id of this marker part.
    package let partId: String
    /// MIME types the backend accepts for the upload, for example `image/png`.
    package let acceptedTypes: [String]
    /// The largest image the backend accepts, in decoded bytes.
    package let maxSizeBytes: Int
}
