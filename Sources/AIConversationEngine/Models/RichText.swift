//
//  RichText.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// Structured prose part returned by the chatbot API.
/// [API ref](https://docs.dialoge.ai/api#model/rich-text-content)
package struct RichText: Decodable, Sendable, Equatable {

    package let partId: String
    package let blocks: [Block]
}

extension RichText {

    /// A rich-text block, discriminated on `type`.
    /// [API ref](https://docs.dialoge.ai/api#model/rich-text-block)
    package enum Block: Decodable, Sendable, Equatable {

        case paragraph(Paragraph)
        case bulletList(BulletList)
        case unknown

        private enum CodingKeys: String, CodingKey {
            case type
        }

        private enum BlockType: String, Decodable {
            case paragraph
            case bulletList = "bullet_list"
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = switch try? container.decode(BlockType.self, forKey: .type) {
            case .paragraph: .paragraph(try Paragraph(from: decoder))
            case .bulletList: .bulletList(try BulletList(from: decoder))
            case .none: .unknown
            }
        }
    }

    /// A paragraph of ordered inline spans.
    /// [API ref](https://docs.dialoge.ai/api#model/rich-text-paragraph-block)
    package struct Paragraph: Decodable, Sendable, Equatable {
        package let spans: [Span]
    }

    /// An unordered bullet list.
    /// [API ref](https://docs.dialoge.ai/api#model/rich-text-bullet-list-block)
    package struct BulletList: Decodable, Sendable, Equatable {

        package let items: [Item]

        /// A single bullet-list item carrying its own ordered spans.
        /// [API ref](https://docs.dialoge.ai/api#model/rich-text-bullet-list-item)
        package struct Item: Decodable, Sendable, Equatable {
            package let spans: [Span]
        }
    }

    /// An inline span, discriminated on `type`.
    /// [API ref](https://docs.dialoge.ai/api#model/rich-text-span)
    package enum Span: Decodable, Sendable, Equatable {

        case text(String)
        case bold(String)
        case strike(String)
        case link(text: String, url: URL)
        case unknown

        private enum CodingKeys: String, CodingKey {
            case type, text, url
        }

        private enum SpanType: String, Decodable {
            case text, bold, strike, link
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = switch try? container.decode(SpanType.self, forKey: .type) {
            case .text: .text(try container.decode(String.self, forKey: .text))
            case .bold: .bold(try container.decode(String.self, forKey: .text))
            case .strike: .strike(try container.decode(String.self, forKey: .text))
            case .link:
                    .link(
                        text: try container.decode(String.self, forKey: .text),
                        url: try container.decode(URL.self, forKey: .url)
                    )
            case .none: .unknown
            }
        }
    }
}
