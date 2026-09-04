//
//  RemoteImageView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-09.
//

import SwiftUI

/// Displays a remote image through the environment's `ImageLoader` — same shape as `AsyncImage`, but
/// the loader dedupes and caches, so the SSE stream's per-delta re-renders resolve from cache
/// instead of restarting the download.
struct RemoteImageView<Content: View, Placeholder: View>: View {

    @Environment(\.imageLoader) private var loader

    private let url: URL
    private let content: (Result<Image, Error>) -> Content
    private let placeholder: () -> Placeholder

    @State private var result: Result<Image, Error>?

    init(
        url: URL,
        @ViewBuilder content: @escaping (Result<Image, Error>) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let result {
                self.content(result)
            } else {
                self.placeholder()
            }
        }
        // `id: url` reloads if the URL changes. On a re-render with stable identity the task keeps
        // its result, and even a fresh view resolves instantly from the loader's cache.
        .task(id: self.url) {
            do {
                let image = try await self.loader.image(for: self.url)
                result = .success(image)
            } catch {
                result = .failure(error)
            }
        }
    }
}
