//
//  PhotoUploadModelsTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("Photo upload — wire models")
struct PhotoUploadModelsTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("image part decodes url, optional fields, and lenient thumbnail")
    func imagePart() throws {
        let part = try self.decoder.decode(Part.self, from: Data("""
        {
          "type": "image",
          "url": "https://cdn.example/a.jpg",
          "attachment_id": "att_1",
          "mime_type": "image/jpeg",
          "size_bytes": 1200,
          "url_expires_at": "2026-09-05T10:00:00Z",
          "thumbnail_url": "not a url",
          "caption": "receipt"
        }
        """.utf8))

        guard case .image(let image) = part else {
            Issue.record("expected image, got \(part)")
            return
        }
        #expect(image.url == URL(string: "https://cdn.example/a.jpg"))
        #expect(image.attachmentId == "att_1")
        #expect(image.mimeType == "image/jpeg")
        #expect(image.sizeBytes == 1200)
        #expect(image.urlExpiresAt == "2026-09-05T10:00:00Z")
        #expect(image.thumbnailUrl == nil, "bad thumbnail must not kill the part")
        #expect(image.caption == "receipt")
    }

    @Test("a malformed image url falls back to unknown")
    func malformedImageIsUnknown() throws {
        let part = try self.decoder.decode(Part.self, from: Data("""
        { "type": "image", "url": "/relative/without/base" }
        """.utf8))
        #expect(part == .unknown)
    }

    @Test("a request_image_upload missing a required field falls back to unknown")
    func imageUploadMarkerMissingFieldIsUnknown() throws {
        let part = try self.decoder.decode(Part.self, from: Data("""
        { "type": "request_image_upload", "part_id": "upload_1" }
        """.utf8))
        #expect(part == .unknown)
    }

    @Test("request_image_upload keeps accepted_types and max_size_bytes when present")
    func imageUploadMarkerFields() throws {
        let part = try self.decoder.decode(Part.self, from: Data("""
        {
          "type": "request_image_upload",
          "part_id": "upload_2",
          "accepted_types": ["image/png"],
          "max_size_bytes": 1000
        }
        """.utf8))

        guard case .requestImageUpload(let marker) = part else {
            Issue.record("expected requestImageUpload, got \(part)")
            return
        }
        #expect(marker.acceptedTypes == ["image/png"])
        #expect(marker.maxSizeBytes == 1000)
    }

    @Test("echo holds the text, then each attachment as posted")
    func echoBuildsUserContent() throws {
        let attachment = try #require(OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: "a.jpg"))

        let contents = ChatProvider.echo(text: "see", attachments: [attachment])

        #expect(contents == [.text(AttributedString("see")), .attachment(attachment)])
    }

    @Test("a message attachment over the 5 MiB cap is rejected before upload")
    func oversizedMessageAttachmentRejected() {
        let atCap = String(repeating: "A", count: OutgoingAttachment.maxEncodedLength)

        #expect(OutgoingAttachment(kind: .image, data: atCap, mime: "image/jpeg", filename: nil) != nil)
        #expect(OutgoingAttachment(kind: .image, data: atCap + "A", mime: "image/jpeg", filename: nil) == nil)
    }

    @Test("an unnamed attachment posts on /actions under a name its MIME type implies")
    func actionFilenameFollowsMime() throws {
        let pdf = try #require(OutgoingAttachment(kind: .image, data: "QQ==", mime: "application/pdf", filename: nil))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let json = try JSONSerialization.jsonObject(with: encoder.encode(pdf)) as? [String: Any]

        #expect(json?["filename"] as? String == "attachment.pdf")
        #expect(json?["mime_type"] as? String == "application/pdf")
        #expect(json?["data_base64"] as? String == "QQ==")
    }
}
