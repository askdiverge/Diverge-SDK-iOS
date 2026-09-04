//
//  ImageLoader.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-09.
//

import SwiftUI

/// Loads remote images once and hands the decoded result to every caller.
///
/// As an  SSE stream each delta re-renders the turn, which recreates the image views.
/// A per-view loader (`AsyncImage`) restarts and cancels its download on every recreation, so under a
/// fast stream a download may never finish. This loader breaks that by owning the work itself:
/// - **Coalescing** — concurrent requests for the same URL await one `Task`, not N downloads.
/// - **Caching** — a finished decode is served synchronously on every later request (bounded by
///   `NSCache`, which evicts under memory pressure — no unbounded growth in the model).
///
/// Because the download lives in a stored `Task` here and not in a view, a view torn down between
/// deltas can't cancel it the next render re-awaits the same task or hits the cache.
actor ImageLoader {

    /// Boxes the `Sendable` `Image` so it can live in `NSCache` (which needs a class value).
    private final class Entry {
        let image: Image
        init(_ image: Image) { self.image = image }
    }

    enum LoadError: Error {
        case decodingFailed
    }

    private let fetch: @Sendable (URL) async throws -> Data
    private let maxPixelSize: CGFloat
    private let cache = NSCache<NSURL, Entry>()
    private var inFlight: [URL: Task<Image, Error>] = [:]

    init(maxPixelSize: CGFloat, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.fetch = fetch
        self.maxPixelSize = maxPixelSize
    }

    func image(for url: URL) async throws -> Image {

        // return cached image
        if let entry = self.cache.object(forKey: url as NSURL) {
            return entry.image
        }

        // A download is already running for this URL — attach to it instead of starting another.
        if let task = self.inFlight[url] {
            return try await task.value
        }

        // Start new download/decoding
        let task = Task.detached(priority: .userInitiated) { [fetch = self.fetch, maxPixelSize = self.maxPixelSize] in
            let data = try await fetch(url)
            guard let image = RemoteImage.decode(data, maxPixelSize: maxPixelSize) else { throw LoadError.decodingFailed }
            return image
        }

        self.inFlight[url] = task
        // persist to cache regardless of caller lifecycle
        Task { await self.persist(task, for: url) }

        return try await task.value
    }

    private func persist(_ task: Task<Image, Error>, for url: URL) async {
        defer { self.inFlight[url] = nil }
        guard let image = try? await task.value else { return }
        self.cache.setObject(Entry(image), forKey: url as NSURL)
    }
}

extension EnvironmentValues {

    /// The image loader used by remote-image views
    var imageLoader: ImageLoader {
        get { self[ImageLoaderKey.self] }
        set { self[ImageLoaderKey.self] = newValue }
    }
}

private struct ImageLoaderKey: EnvironmentKey {
    static let defaultValue = ImageLoader(maxPixelSize: 0) { _ in throw CancellationError() }
}
