//
//  ImageFixtures.swift
//  AIConversationTests
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bitmap fixtures for the attachment tests: a solid-colour `CGImage`, and PNG / JPEG encodings
/// of it with optional container metadata (EXIF, GPS, orientation) to prove what the encoder strips.
enum ImageFixtures {

    struct FixtureError: Error {}

    /// A solid red RGBA bitmap.
    static func image(width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = 255 // R
            pixels[offset + 3] = 255 // A
        }
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else { throw FixtureError() }
        return image
    }

    static func png(width: Int, height: Int) throws -> Data {
        try Self.encode(Self.image(width: width, height: height), as: .png, properties: nil)
    }

    /// A JPEG carrying `properties` in its metadata — e.g. `kCGImagePropertyOrientation` or a
    /// `kCGImagePropertyGPSDictionary`.
    static func jpeg(width: Int, height: Int, properties: [CFString: Any]) throws -> Data {
        try Self.encode(Self.image(width: width, height: height), as: .jpeg, properties: properties)
    }

    /// Container-level properties of an encoded image, as ImageIO reads them back.
    static func properties(of data: Data) -> [CFString: Any] {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [:] }
        return properties
    }

    private static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any]?) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw FixtureError()
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError() }
        return data as Data
    }
}
