//
//  RelativeWidth.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI

struct RelativeWidth: ViewModifier {

    let fraction: CGFloat
    let alignment: Alignment

    init(_ fraction: CGFloat, alignment: Alignment) {
        self.fraction = fraction
        self.alignment = alignment
    }

    func body(content: Content) -> some View {
        content.containerRelativeFrame(.horizontal, alignment: self.alignment) { width, _ in
            width * self.fraction
        }
    }
}
