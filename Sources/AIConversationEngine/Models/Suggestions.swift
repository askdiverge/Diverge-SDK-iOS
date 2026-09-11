//
//  Suggestions.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-04.
//

import Foundation

/// A collection of suggestion cards the visitor can tap to send a follow-up prompt.
/// [API ref](https://docs.dialoge.ai/api#model/suggestions-content)
package struct Suggestions: Decodable, Sendable, Equatable {

    package let partId: String
    package let suggestions: [Card]
}

extension Suggestions {

    /// [API ref](https://docs.dialoge.ai/api#model/suggestion-card)
    package struct Card: Decodable, Sendable, Equatable {

        package let id: String
        package let title: String
        package let description: String?
        /// Soft-fail decode — a malformed `image_url` must not abort the SSE stream.
        package let imageUrl: URL?
        package let promptText: String

        package init(
            id: String,
            title: String,
            description: String?,
            imageUrl: URL?,
            promptText: String
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.imageUrl = imageUrl
            self.promptText = promptText
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.title = try container.decode(String.self, forKey: .title)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)
            self.promptText = try container.decode(String.self, forKey: .promptText)
            let raw = try container.decode(String.self, forKey: .imageUrl)
            self.imageUrl = URL(string: raw)
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, description, imageUrl, promptText
        }
    }
}
