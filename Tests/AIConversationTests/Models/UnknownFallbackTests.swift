//
//  UnknownFallbackTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Guards the forward-compatibility contract of the hand-written decode logic:
/// any discriminator value the server invents in the future must decode to
/// `.unknown` — never throw. A thrown `DecodingError` propagates out of `postSSE`
/// and terminates the entire SSE stream, so one unrecognised value would
/// otherwise kill a live conversation.
@Suite("Unknown-value fallback — stream survival contract")
struct UnknownFallbackTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("unrecognised SSE event name decodes to .unknown")
    func unknownEventName() throws {
        let event = try self.decoder.decode(
            StreamEvent.self,
            from: Data(#"{"type":"some_future_event","data":{"whatever":true}}"#.utf8)
        )
        #expect(event == .unknown)
    }

    @Test("unrecognised delta action decodes to .unknown")
    func unknownDeltaAction() throws {
        let delta = try self.decoder.decode(
            PartDelta.self,
            from: Data(#"{"action":"some_future_action","block_index":0}"#.utf8)
        )
        #expect(delta == .unknown)
    }

    @Test("unrecognised start_part part_type decodes to .unknown")
    func unknownStartPartType() throws {
        let delta = try self.decoder.decode(
            PartDelta.self,
            from: Data(#"{"action":"start_part","part_type":"some_future_part"}"#.utf8)
        )
        #expect(delta == .unknown)
    }

    @Test("suggestions start_part and append_suggestion decode to typed deltas")
    func suggestionsDeltasDecode() throws {
        let start = try self.decoder.decode(
            PartDelta.self,
            from: Data(#"{"action":"start_part","part_type":"suggestions"}"#.utf8)
        )
        #expect(start == .suggestions(.start))

        let append = try self.decoder.decode(
            PartDelta.self,
            from: Data("""
                {"action":"append_suggestion","suggestion":{
                    "id":"outfit_2",
                    "title":"Outfit 2",
                    "image_url":"https://cdn.example.com/outfits/outfit-2.jpg",
                    "prompt_text":"Show me outfit 2"
                }}
                """.utf8)
        )
        #expect(append == .suggestions(.appendSuggestion(.init(
            id: "outfit_2",
            title: "Outfit 2",
            description: nil,
            imageUrl: URL(string: "https://cdn.example.com/outfits/outfit-2.jpg")!,
            promptText: "Show me outfit 2"
        ))))
    }

    @Test("a malformed append_product decodes to .unknown rather than throwing")
    func malformedAppendProductIsUnknown() throws {
        let delta = try self.decoder.decode(
            PartDelta.self,
            from: Data(#"{"action":"append_product","product":{"id":"broken"}}"#.utf8)
        )
        #expect(delta == .unknown)
    }

    @Test("suggestions part type decodes to .suggestions")
    func suggestionsPartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"suggestions","part_id":"part_suggestions_1","suggestions":[{
                    "id":"outfit_2",
                    "title":"Outfit 2",
                    "description":"See all products from this look.",
                    "image_url":"https://cdn.example.com/outfits/outfit-2.jpg",
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
                    description: "See all products from this look.",
                    imageUrl: URL(string: "https://cdn.example.com/outfits/outfit-2.jpg")!,
                    promptText: "Show me outfit 2"
                )
            ]
        )))
    }

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

    @Test("show_contact_form part type decodes with inline fields")
    func showContactFormPartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"show_contact_form","part_id":"part_contact_1","fields":[
                    {"key":"name","label":"Name","type":"text","required":true},
                    {"key":"email","label":"Email","type":"email","required":true},
                    {"key":"message","label":"Message","type":"textarea","required":true}
                ]}
                """.utf8)
        )
        #expect(part == .showContactForm(.init(
            partId: "part_contact_1",
            fields: [
                .init(key: "name", label: "Name", type: .text, required: true),
                .init(key: "email", label: "Email", type: .email, required: true),
                .init(key: "message", label: "Message", type: .textarea, required: true)
            ]
        )))
    }

    @Test("show_support_ticket part type decodes with attachment constraints")
    func showSupportTicketPartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"show_support_ticket","part_id":"part_ticket_1","fields":[
                    {"key":"name","label":"Name","type":"text","required":true}
                ],"attachments_accepted":true,"max_attachment_size_bytes":2097152}
                """.utf8)
        )
        #expect(part == .showSupportTicket(.init(
            partId: "part_ticket_1",
            fields: [.init(key: "name", label: "Name", type: .text, required: true)],
            attachmentsAccepted: true,
            maxAttachmentSizeBytes: 2_097_152
        )))
    }

    @Test("show_support_ticket missing optional fields falls back to contract defaults")
    func showSupportTicketDefaults() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"show_support_ticket","part_id":"part_ticket_1","fields":[]}"#.utf8)
        )
        #expect(part == .showSupportTicket(.init(
            partId: "part_ticket_1",
            fields: [],
            attachmentsAccepted: true,
            maxAttachmentSizeBytes: ShowSupportTicket.defaultMaxAttachmentSizeBytes
        )))
    }

    @Test("show_form part type decodes with form_id, name and min_filled_fields")
    func showFormPartDecodes() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"show_form","part_id":"part_form_1","form_id":"salesLead","name":"Sales lead",
                 "confirmation_text":"Thanks!","fields":[
                    {"key":"email","label":"Email","type":"email","required":true},
                    {"key":"distributor","label":"Distributor","type":"dropdown",
                     "options":["postnord","dhl"],"required":true},
                    {"key":"claim","label":"Claim details","type":"textarea",
                     "visible_when":[{"field":"distributor","operator":"equals","value":"postnord"}]}
                 ],"min_filled_fields":1,"submit_actions":[{"type":"save_lead"}]}
                """.utf8)
        )
        #expect(part == .showForm(.init(
            partId: "part_form_1",
            formId: "salesLead",
            name: "Sales lead",
            confirmationText: "Thanks!",
            fields: [
                .init(key: "email", label: "Email", type: .email, required: true),
                .init(
                    key: "distributor",
                    label: "Distributor",
                    type: .dropdown,
                    required: true,
                    options: ["postnord", "dhl"]
                ),
                .init(
                    key: "claim",
                    label: "Claim details",
                    type: .textarea,
                    visibleWhen: [.init(field: "distributor", value: "postnord")]
                )
            ],
            minFilledFields: 1
        )))
    }

    @Test("FormField missing or unknown type falls back to .text; phone maps to .tel")
    func formFieldTypeLeniency() throws {
        let missing = try self.decoder.decode(
            FormField.self,
            from: Data(#"{"key":"a","label":"A"}"#.utf8)
        )
        #expect(missing.type == .text)

        let unknown = try self.decoder.decode(
            FormField.self,
            from: Data(#"{"key":"b","label":"B","type":"future_widget"}"#.utf8)
        )
        #expect(unknown.type == .text)

        let phone = try self.decoder.decode(
            FormField.self,
            from: Data(#"{"key":"c","label":"C","type":"phone"}"#.utf8)
        )
        #expect(phone.type == .tel)
    }

    @Test("a show_contact_form missing part_id falls back to .unknown without aborting siblings")
    func malformedShowContactFormAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"show_contact_form","fields":[{"key":"name","label":"Name"}]},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts.count == 2)
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test("one malformed element in fields is dropped; its siblings survive")
    func malformedFieldKeepsSiblings() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data("""
                {"type":"show_form","part_id":"part_form_1","form_id":"f","name":"F","fields":[
                    {"key":"name","label":"Name"},
                    {"label":"no key"},
                    "not an object",
                    {"key":"email","label":"Email","type":"email"}
                ]}
                """.utf8)
        )
        guard case .showForm(let form) = part else {
            Issue.record("expected .showForm, got \(part)")
            return
        }
        #expect(form.fields.map(\.key) == ["name", "email"])
    }

    @Test("show_form confirmation_text null and missing both decode to nil")
    func showFormConfirmationNullOrMissing() throws {
        let null = try self.decoder.decode(
            ShowForm.self,
            from: Data("""
                {"part_id":"p","form_id":"f","name":"F","confirmation_text":null,"fields":[]}
                """.utf8)
        )
        let missing = try self.decoder.decode(
            ShowForm.self,
            from: Data("""
                {"part_id":"p","form_id":"f","name":"F","fields":[]}
                """.utf8)
        )
        #expect(null.confirmationText == nil)
        #expect(missing.confirmationText == nil)
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
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

    @Test("unrecognised part type decodes to .unknown")
    func unknownPartType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"some_future_part","part_id":"p_1"}"#.utf8)
        )
        #expect(part == .unknown)
    }

    @Test("unrecognised part type inside a message does not fail sibling parts")
    func unknownPartAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"some_future_part","part_id":"p_1"},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts.count == 2)
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test("unrecognised rich-text block type decodes to .unknown")
    func unknownBlockType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"rich_text","part_id":"p_1","blocks":[{"type":"some_future_block"}]}"#.utf8)
        )
        #expect(part == .richText(.init(partId: "p_1", blocks: [.unknown])))
    }

    @Test("unrecognised span type decodes to .unknown")
    func unknownSpanType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"rich_text","part_id":"p_1","blocks":[{"type":"paragraph","spans":[{"type":"some_future_span"}]}]}"#.utf8)
        )
        #expect(part == .richText(.init(partId: "p_1", blocks: [.paragraph(.init(spans: [.unknown]))])))
    }

    @Test("unrecognised table cell block type decodes to .unknown")
    func unknownTableCellBlockType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"table","part_id":"t_1","headers":[{"blocks":[{"type":"some_future_block"}]}],"rows":[]}"#.utf8)
        )
        #expect(part == .table(.init(
            partId: "t_1",
            caption: nil,
            headers: [.init(blocks: [.unknown])],
            alignments: nil,
            rows: []
        )))
    }

    @Test("unrecognised string-enum values fall back to .unknown")
    func extendableEnumFallback() throws {
        let event = try self.decoder.decode(
            StreamEvent.self,
            from: Data(#"{"type":"status","data":{"status":"some_future_state"}}"#.utf8)
        )
        #expect(event == .status(.init(state: .unknown, message: nil)))
    }
}
