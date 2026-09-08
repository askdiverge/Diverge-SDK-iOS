//
//  Color+Hex.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-23.
//

import Foundation
import SwiftUI

extension Color {

    /// Parses a CSS colour — `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, or `rgba()`.
    /// Integers and `%` components are accepted for the functional forms. Returns `nil` for
    /// any other shape so the caller supplies its own fallback.
    init?(css: String) {
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") || trimmed.range(of: #"^[0-9A-Fa-f]+$"#, options: .regularExpression) != nil {
            self.init(hex: trimmed)
            return
        }
        if let functional = Self.parseFunctionalCSS(trimmed) {
            self = functional
            return
        }
        return nil
    }

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

    private static func parseFunctionalCSS(_ value: String) -> Color? {
        let lower = value.lowercased()
        let hasAlpha = lower.hasPrefix("rgba(")
        guard lower.hasPrefix("rgb(") || hasAlpha else { return nil }
        guard lower.hasSuffix(")") else { return nil }

        let openParen = lower.firstIndex(of: "(")!
        let inner = String(lower[lower.index(after: openParen)..<lower.index(before: lower.endIndex)])
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let expected = hasAlpha ? 4 : 3
        guard parts.count == expected else { return nil }

        guard
            let red = Self.parseCSSComponent(parts[0]),
            let green = Self.parseCSSComponent(parts[1]),
            let blue = Self.parseCSSComponent(parts[2])
        else { return nil }

        let alpha: Double
        if hasAlpha {
            guard let parsed = Self.parseCSSComponent(parts[3]) else { return nil }
            alpha = parsed
        } else {
            alpha = 1
        }

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    private static func parseCSSComponent(_ raw: String) -> Double? {
        if raw.hasSuffix("%") {
            let digits = raw.dropLast().trimmingCharacters(in: .whitespaces)
            guard let value = Double(digits) else { return nil }
            return min(max(value / 100, 0), 1)
        }
        guard let value = Double(raw) else { return nil }
        if value > 1 {
            return min(max(value / 255, 0), 1)
        }
        return min(max(value, 0), 1)
    }
}
