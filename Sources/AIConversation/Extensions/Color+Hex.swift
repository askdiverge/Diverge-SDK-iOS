//
//  Color+Hex.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-23.
//

import Foundation
import SwiftUI

extension Color {

    /// Parses a CSS hex colour — `#RGB`, `#RRGGBB`, or `#RRGGBBAA` (alpha last). Returns
    /// `nil` for any other shape, so the caller supplies its own fallback rather than
    /// rendering a guess.
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: digits).scanHexInt64(&value) else { return nil }

        let red, green, blue, alpha: UInt64
        switch digits.count {
        case 3: // #RGB — expand each nibble (×17 spans 0...255)
            (red, green, blue, alpha) = ((value >> 8 & 0xF) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17, 255)
        case 6: // #RRGGBB
            (red, green, blue, alpha) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF, 255)
        case 8: // #RRGGBBAA
            (red, green, blue, alpha) = (value >> 24 & 0xFF, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
