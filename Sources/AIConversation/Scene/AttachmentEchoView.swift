//
//  AttachmentEchoView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// The visitor's own photo in the echo of a send from this device, framed like any image part.
/// Its `data:` URL is built once per attachment rather than on every render, and the shared
/// image loader decodes the posted JPEG at display size.
struct AttachmentEchoView: View {

    @Environment(\.appearance) private var appearance

    let attachment: OutgoingAttachment

    @State private var image: MessageImage?

    var body: some View {
        Group {
            if let image {
                MessageImageView(image: image, resolveURL: { $0.url })
            } else {
                self.appearance.theme.botSurface
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
            }
        }
        .task(id: self.attachment) {
            self.image = self.attachment.dataURL.map {
                MessageImage(url: $0, mimeType: self.attachment.mimeType, caption: self.attachment.filename)
            }
        }
    }
}
