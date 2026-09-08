//
//  ImageAttachment.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIConversationEngine

/// Encodes a picked photo into an ``OutgoingAttachment`` ready for `POST /messages` or, with
/// ``Options/action(filename:maxDecodedBytes:)``, for `POST /actions`.
///
/// Downsamples to a 1024 px long edge and JPEG-compresses at 0.7 so a multi-megapixel camera
/// shot stays under the API's 5 MiB (6,990,508 base64-char) cap; the tighter 2 MiB action cap
/// gets one retry at a 512 px long edge before failing. Runs off the main actor.
enum ImageAttachment {

    /// Long-edge pixel budget for the upload payload.
    static let maxPixelSize: CGFloat = 1024
    /// Long-edge budget for the pending-chip thumbnail — separate from the 1024 px payload so
    /// several chips do not keep a full-size bitmap each.
    static let chipThumbnailPixelSize: CGFloat = 170
    /// JPEG quality matching the web chatbot's chat-path downscale.
    static let jpegQuality: CGFloat = 0.7

    enum Failure: Error, Equatable {
        case decodingFailed
        case encodingFailed
        case tooLarge
    }

    /// Result of a successful encode — wire payload plus a SwiftUI thumbnail for the chip strip.
    struct Encoded: Sendable {
        let attachment: OutgoingAttachment
        let thumbnail: CGImage
    }

    /// Where the encoded bytes are headed — decides the filename and the size budget.
    struct Options: Sendable, Equatable {
        /// Wire filename (forms invent one; the composer sends none).
        var filename: String?
        /// Long-edge pixel budget before JPEG.
        var maxPixelSize: CGFloat = ImageAttachment.maxPixelSize
        /// Base64 character cap the payload must fit under.
        var maxEncodedLength: Int = OutgoingAttachment.maxEncodedLength

        /// A chat-message image part: no filename, 5 MiB budget.
        static let message = Options()

        /// Chat-message image with an optional tighter decoded-byte budget (livechat).
        /// `nil` / a cap that is not meaningfully below the 5 MiB chat budget keep ``message``.
        static func message(maxDecodedBytes: Int?) -> Options {
            var options = Options.message
            if let decoded = maxDecodedBytes, let cap = Self.tighterEncodedLength(decodedBytes: decoded) {
                options.maxEncodedLength = cap
            }
            return options
        }

        /// An `/actions` `Attachment` (ticket attachment or form file field): synthetic filename,
        /// and the marker's decoded-byte cap converted to a base64 length (4 chars per 3 bytes).
        static func action(filename: String, maxDecodedBytes: Int) -> Options {
            Options(filename: filename, maxEncodedLength: Self.encodedLength(forDecodedBytes: maxDecodedBytes))
        }

        /// Base64 character budget for a decoded-byte cap (4 chars per 3 bytes, floors).
        static func encodedLength(forDecodedBytes decodedBytes: Int) -> Int {
            max(0, (decodedBytes / 3) * 4)
        }

        /// Encoded cap when `decodedBytes` is meaningfully tighter than the 5 MiB chat budget.
        /// Default livechat `5_242_880` encodes 4 chars under ``OutgoingAttachment/maxEncodedLength``
        /// and must not rewrite the encode options.
        static func tighterEncodedLength(decodedBytes: Int) -> Int? {
            let encoded = Self.encodedLength(forDecodedBytes: decodedBytes)
            guard encoded > 0, encoded < OutgoingAttachment.maxEncodedLength - 8 else { return nil }
            return encoded
        }
    }

    /// Downsamples `data`, JPEG-encodes it, and base64-wraps it. Throws ``Failure`` on a
    /// non-image blob, an ImageIO write failure, or a payload that still exceeds the budget
    /// after one retry at half the pixel budget.
    static func encode(_ data: Data, options: Options = .message) throws(Failure) -> Encoded {
        do {
            return try Self.encodeOnce(data, options: options)
        } catch .tooLarge {
            var smaller = options
            smaller.maxPixelSize = options.maxPixelSize / 2
            return try Self.encodeOnce(data, options: smaller)
        }
    }

    private static func encodeOnce(_ data: Data, options: Options) throws(Failure) -> Encoded {
        guard let payloadImage = RemoteImage.thumbnail(data, maxPixelSize: options.maxPixelSize) else {
            throw .decodingFailed
        }
        guard let jpeg = Self.jpegData(from: payloadImage, quality: Self.jpegQuality) else {
            throw .encodingFailed
        }
        let base64 = jpeg.base64EncodedString()
        guard base64.count <= options.maxEncodedLength else {
            throw .tooLarge
        }
        let chip = RemoteImage.thumbnail(data, maxPixelSize: Self.chipThumbnailPixelSize)
            ?? payloadImage
        return Encoded(
            attachment: OutgoingAttachment(
                kind: .image,
                data: base64,
                mime: "image/jpeg",
                filename: options.filename
            ),
            thumbnail: chip
        )
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
