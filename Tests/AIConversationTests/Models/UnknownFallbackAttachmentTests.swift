//
//  UnknownFallbackAttachmentTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// The attachment half of the forward-compatibility contract (see `UnknownFallbackTests`):
/// image / file / upload-prompt parts, `done` payloads and attachment URL resolution must
/// soft-fail to `.unknown` or `nil` rather than throw and tear down the stream.
@Suite("Unknown-value fallback — attachments and done payloads")
struct UnknownFallbackAttachmentTests {

    private let decoder = JSONDecoder.wire()

    @Test("request_image_upload part type decodes with contract fields")
    func requestImageUploadPartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"request_image_upload","part_id":"part_upload_1",
                 "accepted_types":["image/png","image/jpeg"],"max_size_bytes":1048576}
                """.utf8)
        )
        #expect(part == .requestImageUpload(.init(
            partId: "part_upload_1",
            acceptedTypes: ["image/png", "image/jpeg"],
            maxSizeBytes: 1_048_576
        )))
    }

    @Test("request_image_upload missing optional fields falls back to contract defaults")
    func requestImageUploadDefaults() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"request_image_upload","part_id":"part_upload_1"}"#.utf8)
        )
        #expect(part == .requestImageUpload(.init(
            partId: "part_upload_1",
            acceptedTypes: RequestImageUpload.defaultAcceptedTypes,
            maxSizeBytes: RequestImageUpload.defaultMaxSizeBytes
        )))
    }

    @Test("request_image_upload with an empty accepted_types list uses the contract defaults")
    func requestImageUploadEmptyTypesDefault() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"request_image_upload","part_id":"part_upload_1",
                 "accepted_types":[],"max_size_bytes":5242880}
                """.utf8)
        )
        #expect(part == .requestImageUpload(.init(
            partId: "part_upload_1",
            acceptedTypes: RequestImageUpload.defaultAcceptedTypes,
            maxSizeBytes: 5_242_880
        )))
    }

    @Test("request_image_upload with malformed optional fields still decodes with the defaults")
    func requestImageUploadMalformedOptionalsDefault() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"request_image_upload","part_id":"part_upload_1",
                 "accepted_types":["image/png", 7],"max_size_bytes":"5MB"}
                """.utf8)
        )
        #expect(part == .requestImageUpload(.init(
            partId: "part_upload_1",
            acceptedTypes: RequestImageUpload.defaultAcceptedTypes,
            maxSizeBytes: RequestImageUpload.defaultMaxSizeBytes
        )))
    }

    @Test("a request_image_upload missing part_id falls back to .unknown without aborting siblings")
    func malformedRequestImageUploadAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"request_image_upload","accepted_types":["image/png"]},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts.count == 2)
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test("image part type decodes to .image")
    func imagePartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"image","url":"https://cdn.example.com/uploads/receipt.jpg",
                 "thumbnail_url":"https://cdn.example.com/uploads/receipt_thumb.jpg",
                 "caption":"My order receipt"}
                """.utf8)
        )
        #expect(part == .image(.init(
            url: URL(string: "https://cdn.example.com/uploads/receipt.jpg")!,
            thumbnailUrl: URL(string: "https://cdn.example.com/uploads/receipt_thumb.jpg")!,
            caption: "My order receipt"
        )))
    }

    @Test("file part type decodes to .file")
    func filePartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"file","filename":"invoice.pdf","url":"https://cdn.example.com/invoice.pdf",
                 "mime_type":"application/pdf","size_bytes":48231}
                """.utf8)
        )
        #expect(part == .file(.init(
            filename: "invoice.pdf",
            url: URL(string: "https://cdn.example.com/invoice.pdf")!,
            mimeType: "application/pdf",
            sizeBytes: 48231
        )))
    }

    @Test("a file part missing required filename falls back to .unknown without aborting siblings")
    func malformedFileAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"file","url":"https://cdn.example.com/invoice.pdf"},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts.count == 2)
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test("an image part with a malformed url falls back to .unknown without aborting siblings")
    func malformedImageAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"image","url":"not a url","caption":"Receipt"},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts.count == 2)
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test("a done event carrying a malformed image still decodes — the stream is not torn down")
    func doneWithMalformedImageDecodes() throws {
        let event = try self.decoder.decode(
            StreamEvent.self,
            from: Data("""
                {"type":"done","data":{"message":{
                    "message_id":"m_1","role":"assistant","parts":[
                        {"type":"rich_text","part_id":"p_1","blocks":[]},
                        {"type":"image","url":"","caption":"broken"}
                    ],"created_at":"2026-01-01T00:00:00Z"
                }}}
                """.utf8)
        )
        guard case .done(let message, let visitorToken) = event else {
            Issue.record("expected .done, got \(event)")
            return
        }
        #expect(message.parts.count == 2)
        #expect(message.parts[1] == .unknown)
        #expect(visitorToken == nil)
    }

    @Test("a done event carrying visitor_token surfaces the rotated token")
    func doneCarriesVisitorToken() throws {
        let event = try self.decoder.decode(
            StreamEvent.self,
            from: Data("""
                {"type":"done","data":{
                    "visitor_token":"bound.jwt.token",
                    "message":{"message_id":"m_1","role":"assistant","parts":[],
                               "created_at":"2026-01-01T00:00:00Z"}
                }}
                """.utf8)
        )
        guard case .done(_, let visitorToken) = event else {
            Issue.record("expected .done, got \(event)")
            return
        }
        #expect(visitorToken == "bound.jwt.token")
    }

    @Test("a host-less attachment path resolves against the decoder's API base URL")
    func relativeAttachmentResolvesAgainstBase() throws {
        let decoder = JSONDecoder.wire()
        decoder.userInfo[AttachmentURL.baseURLKey] = URL(string: "https://api.example.com")!

        let part = try decoder.decode(
            Part.self,
            from: Data("""
                {"type":"file","filename":"invoice.pdf",
                 "url":"/api/v1/chat/livechat/attachments/abc?token=t"}
                """.utf8)
        )
        #expect(part == .file(.init(
            filename: "invoice.pdf",
            url: URL(string: "https://api.example.com/api/v1/chat/livechat/attachments/abc?token=t")!
        )))
    }

    @Test("a host-less attachment path with no base URL falls back to .unknown")
    func relativeAttachmentWithoutBaseIsUnknown() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"image","url":"/api/v1/chat/livechat/attachments/abc",
                 "thumbnail_url":"/api/v1/chat/livechat/attachments/abc/thumb"}
                """.utf8)
        )
        #expect(part == .unknown)
    }

    @Test("a host-less thumbnail_url soft-fails to nil while an absolute url still decodes")
    func relativeThumbnailSoftFails() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"image","url":"https://cdn.example.com/full.jpg",
                 "thumbnail_url":"/thumb.jpg"}
                """.utf8)
        )
        #expect(part == .image(.init(url: URL(string: "https://cdn.example.com/full.jpg")!)))
    }

    @Test("a data: image URL decodes without a host or API base")
    func dataURLImageDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"image","url":"data:image/png;base64,aGVsbG8=",
                 "caption":"mine.png","mime_type":"image/png"}
                """.utf8)
        )
        #expect(part == .image(.init(
            url: URL(string: "data:image/png;base64,aGVsbG8=")!,
            mimeType: "image/png",
            caption: "mine.png"
        )))
    }

    @Test("a data: file URL decodes without a host or API base")
    func dataURLFileDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"file","filename":"notes.txt",
                 "url":"data:text/plain;base64,aGVsbG8="}
                """.utf8)
        )
        #expect(part == .file(.init(
            filename: "notes.txt",
            url: URL(string: "data:text/plain;base64,aGVsbG8=")!
        )))
    }

    @Test("malformed suggestion image_url soft-fails to nil without aborting decode")
    func malformedSuggestionImageUrl() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"suggestions","part_id":"part_suggestions_1","suggestions":[{
                    "id":"outfit_2",
                    "title":"Outfit 2",
                    "image_url":"",
                    "prompt_text":"Show me outfit 2"
                }]}
                """.utf8)
        )
        #expect(part == .suggestions(.init(
            partId: "part_suggestions_1",
            suggestions: [
                .init(
                    id: "outfit_2",
                    title: "Outfit 2",
                    description: nil,
                    imageUrl: nil,
                    promptText: "Show me outfit 2"
                )
            ]
        )))
    }
}
