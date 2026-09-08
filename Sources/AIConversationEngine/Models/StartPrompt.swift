//
//  StartPrompt.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A tappable starter chip from `GET /api/v1/chat/config`.
///
/// The wire model has no server id — SwiftUI identity is the chip's index in
/// ``StartPromptsView``, so duplicate `prompt_text` rows stay distinct.
///
/// [API ref](https://docs.dialoge.ai/api#model/start-prompt)
package struct StartPrompt: Decodable, Sendable, Equatable {

    package let promptText: String
    /// Substring matched against the host page string; `nil` means global fallback.
    package let urlPattern: String?

    package init(promptText: String, urlPattern: String? = nil) {
        self.promptText = promptText
        self.urlPattern = urlPattern
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.promptText = try container.decode(String.self, forKey: .promptText)
        self.urlPattern = try container.decodeIfPresent(String.self, forKey: .urlPattern)
    }

    private enum CodingKeys: String, CodingKey {
        case promptText, urlPattern
    }
}
