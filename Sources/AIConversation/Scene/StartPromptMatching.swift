//
//  StartPromptMatching.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import AIConversationEngine

/// Ports the legacy widget rule from `selectMatchingPrompts` in startPromptRoutes.ts:
/// literal substring match; when any patterned prompt matches, globals (`urlPattern == nil`)
/// are suppressed; with no page string (or no pattern match), only globals remain.
///
/// The page string is `AIChat.Configuration.contextProvider`, awaited once at
/// `makeView()` bootstrap — hosts should include a path or URL, not only a SKU blurb.
enum StartPromptMatching {

    static func select(
        _ prompts: [StartPrompt],
        page: String?
    ) -> [StartPrompt] {
        let prompts = prompts.filter { !$0.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let page = page ?? ""
        if !page.isEmpty {
            let matching = prompts.filter { prompt in
                guard let pattern = prompt.urlPattern, !pattern.isEmpty else { return false }
                return page.contains(pattern)
            }
            if !matching.isEmpty {
                return matching
            }
        }
        return prompts.filter { $0.urlPattern == nil || $0.urlPattern?.isEmpty == true }
    }
}
