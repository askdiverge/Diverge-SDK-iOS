//
//  Subtitle.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-25.
//

import Foundation
import SwiftUI
import AIConversationEngine

/// The header's disclaimer copy, composed into its rendered form at bootstrap.
struct Subtitle {
    let attributedText: AttributedString
}

extension Subtitle {

    /// Composes the config's subtitle — body copy with the link folded in as an underlined,
    /// tappable run. Either part may be absent; a link following text is spaced off from it.
    init(_ subtitle: ChatConfig.Display.Subtitle) {
        var composed = AttributedString()

        if let text = subtitle.text {
            composed += AttributedString(text)
        }

        if let link = subtitle.link {
            if !composed.characters.isEmpty {
                composed += AttributedString(" ")
            }
            composed += Self.linkRun(link)
        }

        self.attributedText = composed
    }

    private static func linkRun(_ link: ChatConfig.Display.Subtitle.Link) -> AttributedString {
        var run = AttributedString(link.text)
        run.link = link.url
        run.underlineStyle = .single
        return run
    }
}
