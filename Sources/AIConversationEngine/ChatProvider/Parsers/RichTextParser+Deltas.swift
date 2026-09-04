//
//  RichTextParser+Deltas.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-11.
//

import Foundation

extension RichTextParser {

    /// Replays the streamed rich_text deltas into a `RichText`.
    /// Used shared build instructions for parsing as `attributedText`.
    static func attributedText(_ deltas: [PartDelta.RichTextDelta]) -> AttributedString? {
        self.attributedText(Self.reconstruct(deltas))
    }

    private static func reconstruct(_ deltas: [PartDelta.RichTextDelta]) -> RichText {
        var blocks: [RichText.Block] = []

        for delta in deltas {
            switch delta {

            case .startBlock(let index, let type):
                let block = Self.emptyBlock(type)

                if blocks.indices.contains(index) {
                    blocks[index] = block
                } else {
                    blocks.append(block)
                }

            case .appendText(let index, let text):
                Self.append(.text(text), at: index, to: &blocks)

            case .appendSpan(let index, let span):
                Self.append(span, at: index, to: &blocks)

            case .appendItem(let index, let item):
                Self.append(item, at: index, to: &blocks)

            case .start, .endBlock:
                // open/close carry no model change here
                break
            }
        }

        return RichText(partId: "", blocks: blocks)
    }

    private static func append(_ span: RichText.Span, at index: Int, to blocks: inout [RichText.Block]) {
        guard blocks.indices.contains(index), case .paragraph(let paragraph) = blocks[index] else { return }
        blocks[index] = .paragraph(.init(spans: paragraph.spans + [span]))
    }

    private static func append(_ item: RichText.BulletList.Item, at index: Int, to blocks: inout [RichText.Block]) {
        guard blocks.indices.contains(index), case .bulletList(let list) = blocks[index] else { return }
        blocks[index] = .bulletList(.init(items: list.items + [item]))
    }

    private static func emptyBlock(_ type: PartDelta.RichTextDelta.BlockType) -> RichText.Block {
        switch type {
        case .paragraph: .paragraph(.init(spans: []))
        case .bulletList: .bulletList(.init(items: []))
        case .unknown: .unknown
        }
    }
}
