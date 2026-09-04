//
//  ChatConfig.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// Chatbot configuration returned by `GET /api/v1/chat/config`.
///
/// [API ref](https://docs.dialoge.ai/api#model/chatbot-config)
package struct ChatConfig: Decodable, Sendable, Equatable {

    package let display: Display
    package let theme: Theme
}

extension ChatConfig {

    /// A CSS hex colour string (e.g. `"#4F46E5"`).
    package typealias Hex = String
}

extension ChatConfig {

    /// User-facing identity and copy.
    /// [API ref](https://docs.dialoge.ai/api#model/chatbot-display)
    package struct Display: Decodable, Sendable, Equatable {
        package let name: String
        package let avatar: Avatar
        package let welcomeMessage: String?
        package let subtitle: Subtitle?
        package let privacyPolicyUrl: URL

        /// [API ref](https://docs.dialoge.ai/api#model/chatbot-display-avatar)
        package struct Avatar: Decodable, Sendable, Equatable {
            package let url: URL?
        }
    }
}

extension ChatConfig.Display {

    /// Header subtitle — optional body copy and an optional trailing link.
    /// [API ref](https://docs.dialoge.ai/api#model/chatbot-subtitle)
    package struct Subtitle: Decodable, Sendable, Equatable {
        package let text: String?
        package let link: Link?

        /// [API ref](https://docs.dialoge.ai/api#model/chatbot-subtitle-link-value)
        package struct Link: Decodable, Sendable, Equatable {
            package let text: String
            package let url: URL
        }
    }
}

extension ChatConfig {

    /// Visual theme for rendering the chat UI.
    /// [API ref](https://docs.dialoge.ai/api#model/chatbot-theme)
    package struct Theme: Decodable, Sendable, Equatable {
        package let brand: Brand
        package let surface: Surface
        package let header: Header
        package let messages: Messages
        package let input: Input
        package let productCard: ProductCard
        package let font: Font
    }
}

extension ChatConfig.Theme {

    package struct Brand: Decodable, Sendable, Equatable {
        package let primaryColor: ChatConfig.Hex
    }

    package struct Surface: Decodable, Sendable, Equatable {
        package let backgroundColor: ChatConfig.Hex
        package let mutedTextColor: ChatConfig.Hex
    }

    package struct Header: Decodable, Sendable, Equatable {
        package let alignment: String
        package let logo: Logo
        package let button: Button

        package struct Logo: Decodable, Sendable, Equatable {
            package let url: URL
        }

        package struct Button: Decodable, Sendable, Equatable {
            package let backgroundColor: ChatConfig.Hex
            package let iconColor: ChatConfig.Hex
        }
    }

    package struct Messages: Decodable, Sendable, Equatable {
        package let assistant: Assistant
        package let user: User

        package struct Assistant: Decodable, Sendable, Equatable {
            package let backgroundColor: ChatConfig.Hex
            package let textColor: ChatConfig.Hex
            package let avatarSize: String?
            package let borderColor: ChatConfig.Hex?
            package let thinkingBorderGradient: [ChatConfig.Hex]
        }

        package struct User: Decodable, Sendable, Equatable {
            package let backgroundColor: ChatConfig.Hex
            package let textColor: ChatConfig.Hex
            package let borderColor: ChatConfig.Hex?
        }
    }
// TODO: - fix
    package struct Input: Decodable, Sendable, Equatable {
        package let textColor: ChatConfig.Hex
        package let placeholderColor: ChatConfig.Hex
        package let backgroundColor: ChatConfig.Hex?
        package let borderColor: ChatConfig.Hex?
        package let sendButton: SendButton

        package struct SendButton: Decodable, Sendable, Equatable {
            package let iconColor: ChatConfig.Hex?
        }
    }

    package struct ProductCard: Decodable, Sendable, Equatable {
        package let discountPriceColor: ChatConfig.Hex
    }
}

extension ChatConfig.Theme {

    /// Cross-platform font assets.
    /// [API ref](https://docs.dialoge.ai/api#model/chatbot-font)
    package struct Font: Decodable, Sendable, Equatable {
        package let ios: Native
    }
}

extension ChatConfig.Theme.Font {

    /// A hosted native font asset for SDK download and registration.
    /// [API ref](https://docs.dialoge.ai/api#model/chatbot-native-font)
    package struct Native: Decodable, Sendable, Equatable {
        package let assetUrl: URL
        package let sha256: String
        package let format: String
    }
}
