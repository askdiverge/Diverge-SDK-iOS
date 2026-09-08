//
//  MediaCardBody.swift
//  AIConversation
//

import SwiftUI

/// Shared image + title + description chrome for product and suggestion cards.
/// `overlay` sits on the image (e.g. splash badge); `footer` sits under the
/// description (prices, CTAs). A trailing `Spacer` keeps grid cells equal height.
struct MediaCardBody<Overlay: View, Footer: View>: View {

    @Environment(\.appearance) private var appearance

    let imageURL: URL?
    var aspectRatio: CGFloat = 0.7
    let title: String
    let description: String?
    @ViewBuilder var overlay: () -> Overlay
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            ClippedRemoteImage(url: self.imageURL)
                .aspectRatio(self.aspectRatio, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    self.overlay()
                }

            Text(self.title)
                .font(self.appearance.font(size: 13, weight: .bold))
                .foregroundStyle(self.appearance.theme.primaryText)

            if let description = self.description {
                Text(description)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.secondaryText)
            }

            self.footer()

            Spacer(minLength: 0)
        }
    }
}

extension MediaCardBody where Overlay == EmptyView, Footer == EmptyView {

    /// Image + title + description only (suggestion cards).
    init(imageURL: URL?, aspectRatio: CGFloat = 0.7, title: String, description: String?) {
        self.init(
            imageURL: imageURL,
            aspectRatio: aspectRatio,
            title: title,
            description: description,
            overlay: { EmptyView() },
            footer: { EmptyView() }
        )
    }
}
