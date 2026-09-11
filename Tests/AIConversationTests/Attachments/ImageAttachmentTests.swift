//
//  ImageAttachmentTests.swift
//  AIConversationTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ImageAttachment — encode")
struct ImageAttachmentTests {

    @Test("a large bitmap downsamples under the API base64 cap")
    func downsamplesUnderCap() throws {
        let data = try ImageFixtures.png(width: 4000, height: 3000)
        let encoded = try ImageAttachment.encode(data, options: .init(filename: "big.png"))
        #expect(encoded.attachment.kind == .image)
        #expect(encoded.attachment.mime == "image/jpeg")
        #expect(encoded.attachment.filename == "big.png")
        #expect(encoded.attachment.data.count <= OutgoingAttachment.maxEncodedLength)
        #expect(encoded.attachment.dataURL != nil)
        #expect(max(encoded.thumbnail.width, encoded.thumbnail.height) <= Int(ImageAttachment.chipThumbnailPixelSize))
        let payload = try #require(Data(base64Encoded: encoded.attachment.data))
        let payloadProps = ImageFixtures.properties(of: payload)
        let payloadWidth = payloadProps[kCGImagePropertyPixelWidth] as? Int ?? 0
        let payloadHeight = payloadProps[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(max(payloadWidth, payloadHeight) <= Int(ImageAttachment.maxPixelSize))
    }

    @Test("message options honour an optional tighter decoded-byte budget as a base64 length")
    func messageOptionsTighterBudget() {
        var options = ImageAttachment.Options.message(maxDecodedBytes: 2_097_152)
        options.filename = "photo.jpg"
        #expect(options.filename == "photo.jpg")
        #expect(options.maxEncodedLength == 2_796_200) // (2 MiB / 3) * 4 — floors, never over the cap
        #expect(options.maxEncodedLength == ImageAttachment.Options.encodedLength(forDecodedBytes: 2_097_152))
        #expect(options.maxPixelSize == ImageAttachment.maxPixelSize)
    }

    @Test("tighterEncodedLength skips budgets near the default 5 MiB chat cap")
    func tighterEncodedLengthSkipsDefaultChatCap() {
        #expect(ImageAttachment.Options.tighterEncodedLength(decodedBytes: 3_000) == 4_000)
        #expect(ImageAttachment.Options.tighterEncodedLength(decodedBytes: 5_242_880) == nil)
        #expect(ImageAttachment.Options.message(maxDecodedBytes: 3_000).maxEncodedLength == 4_000)
        #expect(
            ImageAttachment.Options.message(maxDecodedBytes: 5_242_880).maxEncodedLength
                == OutgoingAttachment.maxEncodedLength
        )
        #expect(
            ImageAttachment.Options.message(maxDecodedBytes: nil).maxEncodedLength
                == OutgoingAttachment.maxEncodedLength
        )
    }

    @Test("an over-budget encode retries once at half the pixel budget before failing")
    func retriesAtHalfPixelBudget() throws {
        let data = try ImageFixtures.png(width: 1600, height: 1600)
        // A budget the 1024 px pass cannot meet but the 512 px pass can.
        let full = try ImageAttachment.encode(data, options: .message)
        let half = try ImageAttachment.encode(data, options: .init(maxPixelSize: 512))
        let cap = (full.attachment.data.count + half.attachment.data.count) / 2
        let encoded = try ImageAttachment.encode(data, options: .init(maxEncodedLength: cap))
        let payload = try #require(Data(base64Encoded: encoded.attachment.data))
        let after = ImageFixtures.properties(of: payload)
        let width = after[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = after[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(max(width, height) <= 512)
        #expect(encoded.attachment.data.count <= cap)

        // Still too big after the retry → tooLarge.
        #expect(throws: ImageAttachment.Failure.tooLarge) {
            try ImageAttachment.encode(data, options: .init(maxEncodedLength: 16))
        }
    }

    @Test("no filename by default — the picker only offers an asset id, which must not travel")
    func filenameDefaultsToNil() throws {
        let encoded = try ImageAttachment.encode(try ImageFixtures.png(width: 8, height: 8))
        #expect(encoded.attachment.filename == nil)
    }

    @Test("a non-image blob fails to decode")
    func nonImageFails() {
        #expect(throws: ImageAttachment.Failure.decodingFailed) {
            try ImageAttachment.encode(Data("not an image".utf8))
        }
    }

    @Test("EXIF and GPS metadata do not survive re-encoding")
    func stripsEXIFAndGPS() throws {
        let tagged = try ImageFixtures.jpeg(width: 64, height: 48, properties: [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 55.6761,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 12.5683,
                kCGImagePropertyGPSLongitudeRef: "E"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:09:05 10:00:00",
                kCGImagePropertyExifLensModel: "iPhone back camera"
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone"
            ]
        ])
        // The fixture really carries what we claim to strip.
        let before = ImageFixtures.properties(of: tagged)
        #expect(before[kCGImagePropertyGPSDictionary] != nil)

        let encoded = try ImageAttachment.encode(tagged)
        let output = try #require(Data(base64Encoded: encoded.attachment.data))
        let after = ImageFixtures.properties(of: output)

        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        #expect(after[kCGImagePropertyTIFFDictionary] == nil)
        // ImageIO writes a minimal Exif block of its own; only geometry / colour keys may remain.
        let exif = (after[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        let allowed: Set<String> = [
            kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifColorSpace
        ].map { $0 as String }.reduce(into: []) { $0.insert($1) }
        let leftover = Set(exif.keys.map { $0 as String }).subtracting(allowed)
        #expect(leftover.isEmpty, "unexpected EXIF keys survived: \(leftover)")
    }

    @Test("EXIF orientation is baked into the pixels — a rotated capture comes out upright")
    func appliesOrientation() throws {
        // Orientation 6: stored landscape, meant to be shown rotated 90° CW, i.e. portrait.
        let rotated = try ImageFixtures.jpeg(width: 400, height: 200, properties: [
            kCGImagePropertyOrientation: 6
        ])

        let encoded = try ImageAttachment.encode(rotated)
        let output = try #require(Data(base64Encoded: encoded.attachment.data))
        let after = ImageFixtures.properties(of: output)

        #expect(max(encoded.thumbnail.width, encoded.thumbnail.height) <= Int(ImageAttachment.chipThumbnailPixelSize))
        #expect(after[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(after[kCGImagePropertyPixelHeight] as? Int == 400)
        let orientation = after[kCGImagePropertyOrientation] as? Int
        #expect(orientation == nil || orientation == 1)
    }
}
