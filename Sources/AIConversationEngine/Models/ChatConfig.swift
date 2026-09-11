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
    /// Fully resolved dark-scheme palette. Equals ``theme`` when absent (older deployments)
    /// or when the chatbot has no dark theme configured — matching the server's clone.
    package let darkTheme: Theme
    /// Starter chips shown before the first user turn. Empty when absent (older deployments).
    package let startPrompts: [StartPrompt]
    /// Product CTA label and add-to-cart gate. Defaults when absent (older deployments).
    package let productCard: ProductCardSettings
    /// Whether this chatbot's image-analysis flow is on. Omitted on older APIs → `true`, so the
    /// host attachments setting stays the only switch.
    package let imageEnabled: Bool

    package init(
        display: Display,
        theme: Theme,
        darkTheme: Theme? = nil,
        startPrompts: [StartPrompt] = [],
        productCard: ProductCardSettings = ProductCardSettings(),
        imageEnabled: Bool = true
    ) {
        self.display = display
        self.theme = theme
        self.darkTheme = darkTheme ?? theme
        self.startPrompts = startPrompts.filter {
            !$0.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        self.productCard = productCard
        self.imageEnabled = imageEnabled
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.display = try container.decode(Display.self, forKey: .display)
        self.theme = try container.decode(Theme.self, forKey: .theme)
        self.darkTheme = try container.decodeIfPresent(Theme.self, forKey: .darkTheme) ?? self.theme
        let decoded =
            try container.decodeIfPresent(LossyArray<StartPrompt>.self, forKey: .startPrompts)?
            .elements ?? []
        self.startPrompts = decoded.filter {
            !$0.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        self.productCard =
            try container.decodeIfPresent(ProductCardSettings.self, forKey: .productCard)
            ?? ProductCardSettings()
        self.imageEnabled = try container.decodeIfPresent(Bool.self, forKey: .imageEnabled) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case display, theme, darkTheme, startPrompts, productCard, imageEnabled
    }
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
            /// Null when the chatbot has no header logo — matches `/config` `theme.header.logo.url`.
            package let url: URL?
        }

        package struct Button: Decodable, Sendable, Equatable {
            package let backgroundColor: ChatConfig.Hex?
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
        /// Optional — older fixtures and deployments may omit the nested button block.
        package let button: Button?

        package struct Button: Decodable, Sendable, Equatable {
            package let backgroundColor: ChatConfig.Hex
            package let bold: Bool
        }
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
        /// Null when the chatbot uses the platform default font (no custom iOS face).
        package let sha256: String?
        package let format: String
    }
}
