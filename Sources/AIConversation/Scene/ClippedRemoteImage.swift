//
//  ClippedRemoteImage.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// The one remote-image treatment every surface shares — product and suggestion cards, table
/// cells, and assistant image parts: a `botSurface` box the caller sizes (`aspectRatio` /
/// `frame`), filled edge-to-edge by the loaded image and clipped, with the accent spinner while
/// loading. The box holds its size through every state so the layout never jumps.
///
/// `url == nil` renders the bare surface. `failure` is what shows when the load fails; surfaces
/// with their own copy (cards, tables) keep it empty, a standalone image bubble supplies one.
struct ClippedRemoteImage<Failure: View>: View {

    @Environment(\.appearance) private var appearance

    private let url: URL?
    private let failure: () -> Failure

    init(url: URL?, @ViewBuilder failure: @escaping () -> Failure) {
        self.url = url
        self.failure = failure
    }

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    RemoteImageView(url: url) { result in
                        switch result {
                        case .success(let loaded):
                            loaded.resizable().scaledToFill()
                        case .failure:
                            self.failure()
                        }
                    } placeholder: {
                        ProgressView()
                            .tint(self.appearance.theme.accent)
                    }
                }
            }
            .background(self.appearance.theme.botSurface)
            .clipped()
    }
}

extension ClippedRemoteImage where Failure == EmptyView {

    /// A load failure leaves the bare surface — for surfaces whose copy already carries meaning.
    init(url: URL?) {
        self.init(url: url) { EmptyView() }
    }
}
