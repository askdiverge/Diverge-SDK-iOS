#!/usr/bin/env python3
"""Local stand-in for livechat core loop — queue, agent join, typing, messages, close.

POST /__control mutates availability / scripted agent join delay so XCUITests can cover
offline toolbar, handover → waiting (AI still answers), agent join, typing, and close.
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/livechat-evidence.jsonl")

history = []
livechat_messages = []
state = {
    "run": uuid.uuid4().hex[:6],
    "livechat_enabled": True,
    "availability_status": "live",
    "show_livechat_logo": True,
    "attachments_enabled": True,
    "max_attachment_size_bytes": 5242880,
    "status": "inactive",
    "agent_joined_at": None,
    "is_agent_typing": False,
    "active_agent": None,
    "join_after_polls": 2,
    "polls_while_waiting": 0,
    "closed_by": None,
    "seed_marker": True,
    "seed_start_livechat_form": False,
    "omit_livechat_session_on_actions": False,
    "feedback_status": "not_available",  # not_available | pending | submitted
    "feedback_hits": [],
    "feedback_http_status": 200,
    "rate_hits": [],
    "form_hits": [],
    "action_hits": [],
    "handover_hits": [],
    "session_values": {},
    "form_values_http_status": 200,  # PATCH /forms/{id}/values override
    "state_version": 0,
}


def bump_state_version():
    state["state_version"] = int(state.get("state_version") or 0) + 1


def iso(dt=None):
    dt = dt or datetime.now(timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def png(w, h, rgb):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    rows = b"".join(bytes([0]) + bytes(rgb) * w for _ in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def rich(part_id, text):
    return {"type": "rich_text", "part_id": part_id, "blocks": [{"type": "paragraph", "spans": [{"type": "text", "text": text}]}]}


def agent():
    return {
        "agent_id": "00000000-0000-4000-8000-0000000000a1",
        "display_name": "Alice Jensen",
        "avatar_url": None,
    }


def config():
    return {
        "display": {
            "name": "Stand-in bot",
            "avatar": {"url": f"{BASE}/avatar.png"},
            "welcome_message": "Local stand-in — livechat.",
            "subtitle": {"text": "Livechat stand-in", "link": None},
            "privacy_policy_url": "https://example.com/privacy",
        },
        "theme": {
            "brand": {"primary_color": "#4F46E5"},
            "surface": {"background_color": "#FFFFFF", "muted_text_color": "#6B7280"},
            "header": {
                "alignment": "center",
                "logo": {"url": f"{BASE}/logo.png"},
                "button": {"background_color": "#F3F4F6", "icon_color": "#111827"},
            },
            "messages": {
                "assistant": {
                    "background_color": "#F3F4F6",
                    "text_color": "#111827",
                    "border_color": "#FFFFFF",
                    "thinking_border_gradient": ["#FFFFFF", "#4F46E5", "#FFFFFF"],
                },
                "user": {"background_color": "#4F46E5", "text_color": "#FFFFFF"},
            },
            "input": {
                "text_color": "#111827",
                "placeholder_color": "#9CA3AF",
                "background_color": "#FFFFFF",
                "border_color": "#E5E7EB",
                "send_button": {"icon_color": "#4F46E5"},
            },
            "product_card": {"discount_price_color": "#DC2626"},
            "font": {"ios": {"asset_url": f"{BASE}/font.ttf", "sha256": "0" * 64, "format": "ttf"}},
        },
        "product_card": {"open_label": None, "add_to_cart": {"enabled": False}},
        "livechat": {
            "enabled": bool(state["livechat_enabled"]),
            "configured": True,
            "availability_status": state["availability_status"],
            "availability_reason": "manual_live" if state["availability_status"] == "live" else "manual_offline",
            "show_livechat_logo": bool(state["show_livechat_logo"]),
            "attachments_enabled": bool(state.get("attachments_enabled", True)),
            "max_attachment_size_bytes": int(state.get("max_attachment_size_bytes") or 5242880),
        },
        "forms": [
            {
                "form_id": "livechatWaitingContact",
                "name": "Waiting contact",
                "trigger": "livechat_waiting",
                "override_targets": [],
                "submit_actions": [],
            },
            {
                "form_id": "startLivechatLead",
                "name": "Request a person",
                "trigger": "manual",
                "override_targets": [],
                "submit_actions": [{"type": "start_livechat"}],
            },
        ],
        "popup_messages": [],
    }


def start_livechat_form_marker():
    return {
        "type": "show_form",
        "part_id": f"part_start_lc_{state['run']}",
        "form_id": "startLivechatLead",
        "name": "Request a person",
        "confirmation_text": "Connecting you to an agent…",
        "fields": [
            {"key": "email", "label": "Email", "type": "email", "required": True},
        ],
        "min_filled_fields": 1,
        "submit_actions": [{"type": "start_livechat"}],
    }


def waiting_form_definition():
    return {
        "form_id": "livechatWaitingContact",
        "environment": "test",
        "name": "Waiting contact",
        "trigger": "livechat_waiting",
        "trigger_prompt": None,
        "fields": [
            {"key": "email", "label": "Email", "type": "email", "required": False},
            {"key": "order_number", "label": "Order number", "type": "text", "required": False},
        ],
        "min_filled_fields": 1,
        "override_targets": [],
        "submit_actions": [],
    }


def session_state():
    values = []
    for key, value in (state.get("session_values") or {}).items():
        if not value:
            continue
        label = "Email" if key == "email" else ("Order number" if key == "order_number" else key)
        ftype = "email" if key == "email" else "text"
        values.append({
            "key": key,
            "label": label,
            "type": ftype,
            "value": value,
            "updated_at": iso(),
        })
    return {"values": values}


def livechat_state():
    feedback_status = state.get("feedback_status") or "not_available"
    if state["status"] == "closed" and feedback_status == "not_available":
        # Closing always opens CSAT until submitted or explicitly overridden.
        feedback_status = "pending"
        state["feedback_status"] = "pending"
    return {
        "environment": "test",
        "status": state["status"],
        "platform": "mobile_app",
        "active_agent": state["active_agent"],
        "is_agent_typing": bool(state["is_agent_typing"]),
        "language": "english",
        "feedback": {
            "status": feedback_status,
            "submitted_at": iso() if feedback_status == "submitted" else None,
        },
        "updated_at": iso(),
        "agent_joined_at": state["agent_joined_at"],
        "closed_at": iso() if state["status"] == "closed" else None,
        "closed_by": state["closed_by"],
        "closed_by_agent_id": None,
        "close_reason": None,
        "state_version": int(state.get("state_version") or 0),
    }


def seed():
    history.clear()
    livechat_messages.clear()
    state["status"] = "inactive"
    state["agent_joined_at"] = None
    state["is_agent_typing"] = False
    state["active_agent"] = None
    state["polls_while_waiting"] = 0
    state["closed_by"] = None
    state["feedback_status"] = "not_available"
    state["feedback_hits"] = []
    state["feedback_http_status"] = 200
    state["rate_hits"] = []
    state["form_hits"] = []
    state["action_hits"] = []
    state["handover_hits"] = []
    state["session_values"] = {}
    state["form_values_http_status"] = 200
    state["state_version"] = 0
    now = datetime.now(timezone.utc)
    parts = [rich(f"part_welcome_{state['run']}", "How can I help?")]
    if state["seed_marker"]:
        parts.append({"type": "request_human_agent", "part_id": f"part_human_{state['run']}"})
    if state.get("seed_start_livechat_form"):
        parts.append(start_livechat_form_marker())
    history.append({
        "message_id": f"msg_welcome_{state['run']}",
        "role": "assistant",
        "created_at": iso(now),
        "parts": parts,
    })


def evidence(obj):
    with open(EVIDENCE, "a") as f:
        f.write(json.dumps({"ts": time.time(), **obj}) + "\n")


def sse(handler, events):
    handler.send_response(200)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-cache")
    handler.end_headers()
    try:
        for event, data in events:
            handler.wfile.write(f"event: {event}\ndata: {json.dumps(data)}\n\n".encode())
            handler.wfile.flush()
    except (BrokenPipeError, ConnectionResetError):
        pass


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(f'{self.client_address[0]} - "{self.command} {self.path}"\n')

    def _json(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _empty(self, code):
        self.send_response(code)
        self.end_headers()

    def _body(self):
        n = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/v1/chat/config":
            return self._json(200, config())
        if path == "/api/v1/chat/messages":
            return self._json(200, {"messages": list(reversed(history)), "next_cursor": None, "has_more": False})
        if path == "/api/v1/chat/livechat/state":
            if state["status"] == "waiting":
                state["polls_while_waiting"] += 1
                if state["polls_while_waiting"] >= int(state["join_after_polls"]):
                    state["status"] = "active"
                    state["active_agent"] = agent()
                    state["agent_joined_at"] = iso()
                    state["is_agent_typing"] = True
                    bump_state_version()
                    livechat_messages.append({
                        "message_id": f"lc_hello_{state['run']}",
                        "role": "agent",
                        "agent": agent(),
                        "parts": [rich(f"part_agent_hello_{state['run']}", "Hi, I'm Alice. How can I help?")],
                        "created_at": iso(),
                        "sequence_number": len(livechat_messages) + 1,
                    })
                    evidence({"event": "agent_joined", "run": state["run"]})
            return self._json(200, livechat_state())
        if path == "/api/v1/chat/livechat/messages":
            qs = parse_qs(parsed.query)
            after = int(qs.get("after_sequence_number", ["0"])[0] or 0)
            msgs = [m for m in livechat_messages if m["sequence_number"] > after]
            return self._json(200, {"messages": msgs, "has_more": False})
        if path == "/api/v1/chat/session":
            auth = self.headers.get("Authorization", "")
            evidence({"event": "get_session", "auth": auth, "run": state["run"]})
            return self._json(200, session_state())
        if path.startswith("/api/v1/chat/forms/") and not path.endswith("/values"):
            form_id = path.rsplit("/", 1)[-1]
            auth = self.headers.get("Authorization", "")
            evidence({"event": "get_form", "form_id": form_id, "auth": auth, "run": state["run"]})
            if form_id != "livechatWaitingContact":
                return self._json(404, {"error": {"code": "not_found", "message": "unknown form"}})
            return self._json(200, waiting_form_definition())
        if path in ("/avatar.png", "/logo.png"):
            raw = png(64, 64, (79, 70, 229))
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if path == "/font.ttf":
            return self._empty(404)
        self._empty(404)

    def do_POST(self):
        path = urlparse(self.path).path
        body = self._body()
        if path == "/__control":
            # Mid-session agent join without wiping AI/livechat history.
            if body.get("join_agent"):
                state["status"] = "active"
                state["active_agent"] = agent()
                state["agent_joined_at"] = iso()
                state["is_agent_typing"] = True
                bump_state_version()
                if not any(m.get("message_id", "").startswith("lc_hello_") for m in livechat_messages):
                    livechat_messages.append({
                        "message_id": f"lc_hello_{state['run']}",
                        "role": "agent",
                        "agent": agent(),
                        "parts": [rich(f"part_agent_hello_{state['run']}", "Hi, I'm Alice. How can I help?")],
                        "created_at": iso(),
                        "sequence_number": len(livechat_messages) + 1,
                    })
                evidence({"event": "join_agent", "run": state["run"]})
                return self._json(200, {"ok": True, "run": state["run"], "state": livechat_state()})
            if "set_typing" in body:
                state["is_agent_typing"] = bool(body["set_typing"])
                evidence({"event": "set_typing", "run": state["run"], "typing": state["is_agent_typing"]})
                return self._json(200, {"ok": True, "run": state["run"], "state": livechat_state()})
            if body.get("close_agent"):
                state["status"] = "closed"
                state["closed_by"] = "agent"
                state["is_agent_typing"] = False
                state["feedback_status"] = "pending"
                bump_state_version()
                livechat_messages.append({
                    "message_id": f"lc_bye_{state['run']}",
                    "role": "agent",
                    "agent": agent(),
                    "parts": [rich(f"part_agent_bye_{state['run']}", "Thanks, closing now.")],
                    "created_at": iso(),
                    "sequence_number": len(livechat_messages) + 1,
                })
                evidence({"event": "close_agent", "run": state["run"]})
                return self._json(200, {"ok": True, "run": state["run"], "state": livechat_state()})
            if body.get("reset"):
                state["run"] = uuid.uuid4().hex[:6]
                # Apply seed flags before seed() so the welcome message matches the control body.
                for key in (
                    "livechat_enabled", "availability_status", "show_livechat_logo",
                    "attachments_enabled", "max_attachment_size_bytes",
                    "join_after_polls", "seed_marker", "seed_start_livechat_form",
                    "omit_livechat_session_on_actions", "is_agent_typing",
                    "feedback_http_status", "form_values_http_status",
                ):
                    if key in body:
                        state[key] = body[key]
                seed()
            else:
                # Mid-session flag updates — empty `{}` must not wipe hit logs.
                for key in (
                    "livechat_enabled", "availability_status", "show_livechat_logo",
                    "attachments_enabled", "max_attachment_size_bytes",
                    "join_after_polls", "seed_marker", "seed_start_livechat_form",
                    "omit_livechat_session_on_actions", "is_agent_typing",
                    "feedback_http_status", "form_values_http_status",
                ):
                    if key in body:
                        state[key] = body[key]
            if "feedback_status" in body:
                state["feedback_status"] = body["feedback_status"]
            forced = body.get("force_status")
            if forced:
                state["status"] = forced
                bump_state_version()
                if forced == "active":
                    state["active_agent"] = agent()
                    state["agent_joined_at"] = iso()
                    # Re-seed agent hello when forcing active (after reset seed wiped messages).
                    if not any(m.get("message_id", "").startswith("lc_hello_") for m in livechat_messages):
                        livechat_messages.append({
                            "message_id": f"lc_hello_{state['run']}",
                            "role": "agent",
                            "agent": agent(),
                            "parts": [rich(f"part_agent_hello_{state['run']}", "Hi, I'm Alice. How can I help?")],
                            "created_at": iso(),
                            "sequence_number": 1,
                        })
                if forced == "closed":
                    state["closed_by"] = body.get("closed_by", "agent")
                    state["feedback_status"] = body.get("feedback_status", "pending")
            evidence({"event": "control", "body": body, "run": state["run"]})
            return self._json(200, {
                "ok": True,
                "run": state["run"],
                "state": livechat_state(),
                "feedback_hits": state["feedback_hits"],
                "rate_hits": state["rate_hits"],
                "form_hits": state["form_hits"],
                "action_hits": state["action_hits"],
                "handover_hits": state["handover_hits"],
            })
        if path == "/api/v1/chat/livechat/handover":
            auth = self.headers.get("Authorization", "")
            hit = {"auth": auth, "body": body}
            state["handover_hits"].append(hit)
            if state["availability_status"] != "live" or not state["livechat_enabled"]:
                evidence({"event": "handover_409", "body": body, "run": state["run"]})
                return self._json(409, {"error": "Livechat is currently offline"})
            state["status"] = "waiting"
            state["polls_while_waiting"] = 0
            bump_state_version()
            # Record client_context when present (optional — do not require it).
            evidence({
                "event": "handover",
                "body": body,
                "client_context": body.get("client_context"),
                "run": state["run"],
            })
            return self._json(200, {"status": "waiting", "livechat_session_id": f"ls_{state['run']}"})
        if path == "/api/v1/chat/livechat/messages":
            if state["status"] != "active":
                return self._json(409, {"error": "no active session"})
            auth = self.headers.get("Authorization", "")
            text = ""
            image_parts = []
            for part in body.get("message", {}).get("parts", []):
                if part.get("type") == "text":
                    text = part.get("text", "")
                elif part.get("type") == "image":
                    data = part.get("data") or ""
                    image_parts.append({
                        "mime": part.get("mime"),
                        "data_len": len(data),
                    })
            seq = len(livechat_messages) + 1
            msg = {
                "message_id": f"lc_user_{seq}",
                "role": "user",
                "parts": [rich(f"part_user_{seq}", text or ("(photo)" if image_parts else ""))],
                "created_at": iso(),
                "sequence_number": seq,
            }
            livechat_messages.append(msg)
            state["is_agent_typing"] = False
            evidence({
                "event": "livechat_send",
                "text": text,
                "auth": auth,
                "image_parts": image_parts,
                "run": state["run"],
            })
            return self._json(200, {"message": msg, "livechat_session": livechat_state(), **msg})
        if path == "/api/v1/chat/actions":
            auth = self.headers.get("Authorization", "")
            hit = {"auth": auth, "body": body}
            state["action_hits"].append(hit)
            evidence({"event": "actions_submit", "auth": auth, "body": body, "run": state["run"]})
            if state.get("omit_livechat_session_on_actions"):
                return self._json(200, {
                    "submission_id": f"sub_{state['run']}",
                    "confirmation_text": "Thanks — received.",
                })
            state["status"] = "waiting"
            state["polls_while_waiting"] = 0
            bump_state_version()
            return self._json(200, {
                "submission_id": f"sub_{state['run']}",
                "confirmation_text": "Connecting you to an agent…",
                "livechat_session": {
                    "livechat_session_id": f"ls_{state['run']}",
                    "environment": "test",
                    "status": "waiting",
                    "platform": "mobile_app",
                    "language": "english",
                    "requested_at": iso(),
                    "agent_joined_at": None,
                    "closed_at": None,
                    "closed_by": None,
                    "closed_by_agent_id": None,
                    "close_reason": None,
                },
            })
        if path == "/api/v1/chat/livechat/typing":
            evidence({"event": "visitor_typing", "body": body, "run": state["run"]})
            return self._json(200, {"livechat_session_id": f"ls_{state['run']}", "environment": "test", "is_typing": body.get("is_typing", False), "updated_at": iso()})
        if path == "/api/v1/chat/livechat/close":
            state["status"] = "closed"
            state["closed_by"] = "customer"
            state["is_agent_typing"] = False
            state["feedback_status"] = "pending"
            bump_state_version()
            evidence({"event": "close", "body": body, "run": state["run"]})
            return self._json(200, livechat_state())
        if path == "/api/v1/chat/livechat/feedback":
            auth = self.headers.get("Authorization", "")
            status_code = int(state.get("feedback_http_status") or 200)
            hit = {"auth": auth, "body": body, "status": status_code}
            state["feedback_hits"].append(hit)
            evidence({"event": "livechat_feedback", **hit, "run": state["run"]})
            if status_code == 401:
                return self._json(401, {"error": {"code": "unauthorized", "message": "gone"}})
            if status_code == 409:
                return self._json(409, {
                    "error": {
                        "code": "conflict",
                        "message": "Feedback has already been submitted for this livechat session",
                    }
                })
            if status_code != 200:
                return self._json(status_code, {"error": {"code": "internal", "message": "boom"}})
            if state["status"] != "closed":
                return self._json(409, {
                    "error": {
                        "code": "conflict",
                        "message": "A closed livechat session is required before feedback can be submitted",
                    }
                })
            if state.get("feedback_status") == "submitted":
                return self._json(409, {
                    "error": {
                        "code": "conflict",
                        "message": "Feedback has already been submitted for this livechat session",
                    }
                })
            state["feedback_status"] = "submitted"
            rating = body.get("rating")
            feedback = body.get("feedback")
            return self._json(200, {
                "livechat_session_id": f"ls_{state['run']}",
                "environment": "test",
                "status": "submitted",
                "rating": rating,
                "feedback": feedback,
                "submitted_at": iso(),
            })
        if path == "/api/v1/chat/messages":
            if state["status"] == "active":
                evidence({"event": "ai_send_409", "run": state["run"]})
                return self._json(409, {"error": "An active livechat session is in progress"})
            auth = self.headers.get("Authorization", "")
            text = ""
            for part in body.get("message", {}).get("parts", []):
                if part.get("type") == "text":
                    text = part.get("text", "")
            mid = f"msg_user_{uuid.uuid4().hex[:6]}"
            reply_id = f"msg_bot_{uuid.uuid4().hex[:6]}"
            history.append({"message_id": mid, "role": "user", "created_at": iso(), "parts": [rich(f"part_{mid}", text)]})
            reply_text = f"AI still here while you wait — got: {text}" if state["status"] == "waiting" else f"AI reply to: {text}"
            reply = {"message_id": reply_id, "role": "assistant", "created_at": iso(), "parts": [rich(f"part_{reply_id}", reply_text)]}
            history.append(reply)
            evidence({"event": "ai_send", "text": text, "auth": auth[:24], "run": state["run"]})
            reply_part = reply["parts"][0]
            return sse(self, [
                ("part", {"part": reply_part}),
                ("done", {"message": reply, "visitor_token": "visitor-bound-token"}),
            ])
        if path == "/api/v1/chat/rate":
            auth = self.headers.get("Authorization", "")
            state["rate_hits"].append({"auth": auth, "body": body})
            evidence({"event": "rate", "body": body, "auth": auth, "run": state["run"]})
            return self._empty(200)
        self._empty(404)

    def do_PATCH(self):
        path = urlparse(self.path).path
        body = self._body()
        if path.endswith("/values") and path.startswith("/api/v1/chat/forms/"):
            # /api/v1/chat/forms/{id}/values
            parts = path.strip("/").split("/")
            form_id = parts[4] if len(parts) >= 6 else ""
            auth = self.headers.get("Authorization", "")
            status_code = int(state.get("form_values_http_status") or 200)
            hit = {"auth": auth, "body": body, "status": status_code, "form_id": form_id}
            state["form_hits"].append(hit)
            evidence({"event": "patch_form_values", **hit, "run": state["run"]})
            if status_code == 422:
                return self._json(422, {
                    "error": {"code": "validation_error", "message": "invalid values"}
                })
            if status_code != 200:
                return self._json(status_code, {"error": {"code": "internal", "message": "boom"}})
            if state["status"] != "waiting":
                return self._json(409, {
                    "error": {
                        "code": "conflict",
                        "message": "Session form values can only be saved while waiting for an agent",
                    }
                })
            values = body.get("values") or {}
            if not isinstance(values, dict):
                return self._json(422, {
                    "error": {"code": "validation_error", "message": "values must be an object"}
                })
            merged = dict(state.get("session_values") or {})
            for key, value in values.items():
                if isinstance(value, str) and value.strip():
                    merged[str(key)] = value.strip()
            state["session_values"] = merged
            return self._json(200, session_state())
        self._empty(404)


if __name__ == "__main__":
    seed()
    print(f"livechat stand-in on {BASE}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
