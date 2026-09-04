//
//  RemoteImage.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-23.
//

import Foundation
import ImageIO
import SwiftUI

/// Decodes image bytes into a SwiftUI `Image`, downsampling to `maxPixelSize` on the larger edge.
///
/// Image I/O decodes straight to the bounded size via a thumbnail, so an oversized source (e.g. a
/// 1300×1700 product photo shown in a small cell) never materialises as a full bitmap in memory.
/// `maxPixelSize` should be the display size × screen scale.
enum RemoteImage {

    static func decode(_ data: Data, maxPixelSize: CGFloat) -> Image? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        return Image(decorative: image, scale: 1)
    }
}
