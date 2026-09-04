//
//  SendMessageRequest.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-04.
//

import Foundation

/// Request body for
/// [API ref](https://docs.dialoge.ai/api#operation/Messages_send)
struct SendMessageRequest: Encodable, Sendable, Equatable {
    let message: Payload
    let context: Context?
}

extension SendMessageRequest {

    struct Payload: Encodable, Sendable, Equatable {
        let parts: [Part]
    }

    struct Context: Encodable, Sendable, Equatable {
        let page: String
    }

    /// An image uploaded by the user
    /// [API ref](https://docs.dialoge.ai/api#model/image-input)
    struct Input: Encodable, Sendable, Equatable {
        let data: String
        let mime: String
        let filename: String?
    }

    enum Part: Encodable, Sendable, Equatable {

        case text(String)
        case image(Input)
        case file(Input)

        private var typeName: String {
            switch self {
            case .text: "text"
            case .image: "image"
            case .file: "file"
            }
        }

        private enum CodingKey: String, Swift.CodingKey {
            case type, text
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKey.self)
            try container.encode(typeName, forKey: .type)

            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)

            case .image(let data), .file(let data):
                try data.encode(to: encoder)
            }
        }
    }
}
