//
//  ChatServiceActionTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// What leaves the device on `POST /actions` — dictionary field keys must survive verbatim
/// (no snake_case rewrite), and a 401 must surface as session expiry.
@Suite("ChatService — form actions on the wire")
struct ChatServiceActionTests {

    @Test("a camelCase field key survives verbatim on the wire")
    func camelCaseFieldKeySurvives() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(body: Data(#"{"submission_id":"sub_1","confirmation_text":"Thanks"}"#.utf8))
        ])

        let response = try await sut.submitAction(SubmitActionRequest(
            partId: "part_contact_1",
            action: .contactForm(fields: [
                "orderNumber": "ABC-123",
                "email": "jane@example.com"
            ])
        ))

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/actions")
        #expect(request.header("Authorization") == "Bearer host-token")
        let json = try #require(request.json)
        #expect(json["part_id"] as? String == "part_contact_1")
        let action = try #require(json["action"] as? [String: Any])
        #expect(action["type"] as? String == "contact_form")
        let fields = try #require(action["fields"] as? [String: String])
        #expect(fields["orderNumber"] == "ABC-123", "must not become order_number")
        #expect(fields["email"] == "jane@example.com")
        #expect(response.submissionId == "sub_1")
        #expect(response.confirmationText == "Thanks")
    }

    @Test("support_ticket encodes name/email/message and attachment snake_case fields")
    func supportTicketEncodes() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(body: Data(#"{"submission_id":"sub_2"}"#.utf8))
        ])

        _ = try await sut.submitAction(SubmitActionRequest(
            partId: "part_ticket_1",
            action: .supportTicket(
                name: "Jane",
                email: "jane@example.com",
                message: "Broken",
                attachments: [
                    OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: "photo.jpg")
                ]
            )
        ))

        let action = try #require(script.requests.first?.json?["action"] as? [String: Any])
        #expect(action["type"] as? String == "support_ticket")
        #expect(action["name"] as? String == "Jane")
        let attachments = try #require(action["attachments"] as? [[String: Any]])
        #expect(attachments[0]["filename"] as? String == "photo.jpg")
        #expect(attachments[0]["mime_type"] as? String == "image/jpeg")
        #expect(attachments[0]["data_base64"] as? String == "QQ==")
    }

    @Test("form_submission encodes values and files keyed by FormField.key")
    func formSubmissionEncodes() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(body: Data(#"{"submission_id":"sub_3"}"#.utf8))
        ])

        _ = try await sut.submitAction(SubmitActionRequest(
            partId: "part_form_1",
            action: .formSubmission(
                formId: "salesLead",
                values: ["companyName": "Acme"],
                files: [
                    "photo": OutgoingAttachment(
                        kind: .image,
                        data: "QQ==",
                        mime: "image/jpeg",
                        filename: "photo.jpg"
                    )
                ]
            )
        ))

        let action = try #require(script.requests.first?.json?["action"] as? [String: Any])
        #expect(action["type"] as? String == "form_submission")
        #expect(action["form_id"] as? String == "salesLead")
        let values = try #require(action["values"] as? [String: String])
        #expect(values["companyName"] == "Acme", "must not become company_name")
        let files = try #require(action["files"] as? [String: [String: Any]])
        #expect(files["photo"]?["filename"] as? String == "photo.jpg")
    }

    @Test("a 401 on /actions surfaces as sessionExpired")
    func unauthorizedSurfacesExpiry() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])

        do {
            _ = try await sut.submitAction(SubmitActionRequest(
                partId: "part_contact_1",
                action: .contactForm(fields: ["email": "a@b.c"])
            ))
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            // expected
        } catch {
            Issue.record("expected sessionExpired, got \(error)")
        }
    }

    @Test("400 / 500 on /actions surface as an unhandled transport error", arguments: [400, 500])
    func serverErrorsAreTransport(status: Int) async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: status, body: Data("{\"error\":\"nope\"}".utf8))
        ])

        do {
            _ = try await sut.submitAction(SubmitActionRequest(
                partId: "part_contact_1",
                action: .contactForm(fields: ["email": "a@b.c"])
            ))
            Issue.record("expected a transport error")
        } catch ChatServiceError.transport(.http(.unhandled(let code))) {
            #expect(code == status)
        } catch {
            Issue.record("expected transport(.http(.unhandled)), got \(error)")
        }
    }

    @Test("409 on /actions surfaces as ChatServiceError.conflict")
    func conflictIsDistinguished() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 409, body: Data("{\"error\":\"offline\"}".utf8))
        ])

        do {
            _ = try await sut.submitAction(SubmitActionRequest(
                partId: "part_contact_1",
                action: .contactForm(fields: ["email": "a@b.c"])
            ))
            Issue.record("expected conflict")
        } catch ChatServiceError.conflict {
            // expected
        } catch {
            Issue.record("expected conflict, got \(error)")
        }
    }

    @Test("a start_livechat response carries livechat_session.status for the poller")
    func livechatSessionDecoded() async throws {
        let body = """
        {"submission_id":"sub_9","confirmation_text":"Connecting…",
         "livechat_session":{"livechat_session_id":"ls_1","environment":"test","status":"waiting","platform":"mobile_app","language":"en","requested_at":"2026-01-01T00:00:00Z","agent_joined_at":null,"closed_at":null,"closed_by":null,"closed_by_agent_id":null,"close_reason":null}}
        """
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data(body.utf8))
        ])
        let response = try await sut.submitAction(SubmitActionRequest(
            partId: "part_livechat_1",
            action: .formSubmission(formId: "handoverForm", values: ["email": "a@b.c"], files: nil)
        ))
        #expect(response.submissionId == "sub_9")
        #expect(response.confirmationText == "Connecting…")
        #expect(response.livechatSession?.status == .waiting)
        #expect(response.livechatSession?.shouldAdoptPoller == true)
    }

    @Test("malformed livechat_session is dropped; confirmation still decodes")
    func livechatSessionMalformed() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(
            SubmitActionResponse.self,
            from: Data("{\"submission_id\":\"s\",\"livechat_session\":42}".utf8)
        )
        #expect(response.livechatSession == nil)
        #expect(response.submissionId == "s")
    }

    @Test("confirmation_text null and missing both decode to nil")
    func confirmationTextNullOrMissing() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let null = try decoder.decode(
            SubmitActionResponse.self,
            from: Data("{\"submission_id\":\"s\",\"confirmation_text\":null}".utf8)
        )
        let missing = try decoder.decode(SubmitActionResponse.self, from: Data("{\"submission_id\":\"s\"}".utf8))
        let malformed = try decoder.decode(
            SubmitActionResponse.self,
            from: Data("{\"submission_id\":\"s\",\"confirmation_text\":42}".utf8)
        )
        #expect(null.confirmationText == nil)
        #expect(missing.confirmationText == nil)
        #expect(malformed.confirmationText == nil)
    }
}
