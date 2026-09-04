//
//  HeaderLogo.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-05.
//

import SwiftUI

struct HeaderLogo {
    let image: Image
    let alignment: Alignment

    init(image: Image, alignment: String) {
        self.image = image
        self.alignment = switch alignment {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }
}
