#!/usr/bin/env python3
"""Local stand-in for contact / support-ticket / custom form markers + POST /actions.

Seeds history with all three form kinds so cards appear at open. Text sends that do not
look like a form submission get a short reply. POST /api/v1/chat/actions validates the
part_id against the latest assistant actionable part and returns confirmation_text.
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/forms-evidence.jsonl")
history = []
submissions = []
# Mutable per-run state: part ids carry a run suffix so the app's persisted "submitted"
# set (keyed by part id) cannot bleed from one flow into the next; `fail_next_action`
# makes the next POST /actions answer 500 once.
state = {"run": uuid.uuid4().hex[:6], "fail_next_action": False}


def iso(dt):
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


CONTACT_FIELDS = [
    {"key": "name", "label": "Name", "type": "text", "required": True},
    {"key": "email", "label": "Email", "type": "email", "required": True},
    {"key": "message", "label": "Message", "type": "textarea", "required": True},
]

TICKET_FIELDS = [
    {"key": "name", "label": "Name", "type": "text", "required": True},
    {"key": "email", "label": "Email", "type": "email", "required": True},
    {"key": "message", "label": "Describe your issue", "type": "textarea", "required": True},
]

CUSTOM_FIELDS = [
    {"key": "email", "label": "Email", "type": "email", "required": True},
    {"key": "distributor", "label": "Distributor", "type": "dropdown", "required": True, "options": ["postnord", "dhl"]},
    {
        "key": "claim",
        "label": "Claim details",
        "type": "textarea",
        "required": True,
        "visible_when": [{"field": "distributor", "operator": "equals", "value": "postnord"}],
    },
    {"key": "photo", "label": "Photo", "type": "file", "required": False},
]


def contact_marker(part_id=None):
    return {"type": "show_contact_form", "part_id": part_id or f"part_contact_{state['run']}", "fields": CONTACT_FIELDS}


def ticket_marker(part_id=None):
    return {
        "type": "show_support_ticket",
        "part_id": part_id or f"part_ticket_{state['run']}",
        "fields": TICKET_FIELDS,
        "attachments_accepted": True,
        "max_attachment_size_bytes": 2097152,
    }


def custom_marker(part_id=None):
    return {
        "type": "show_form",
        "part_id": part_id or f"part_form_{state['run']}",
        "form_id": "salesLead",
        "name": "Sales lead",
        "confirmation_text": "Thanks — your lead is in.",
        "fields": CUSTOM_FIELDS,
        "min_filled_fields": 1,
        "submit_actions": [{"type": "save_lead"}],
    }


CONFIG = {
    "display": {
        "name": "Stand-in bot",
        "avatar": {"url": f"{BASE}/avatar.png"},
        "welcome_message": "Local stand-in — contact, ticket and custom forms below.",
        "subtitle": {"text": "Forms stand-in", "link": None},
        "privacy_policy_url": "https://example.com/privacy",
    },
    "theme": {
        "brand": {"primary_color": "#4F46E5"},
        "surface": {"background_color": "#FFFFFF", "muted_text_color": "#6B7280"},
        "header": {"alignment": "left", "logo": {"url": f"{BASE}/logo.png"}, "button": {"background_color": "#4F46E5", "icon_color": "#FFFFFF"}},
        "messages": {
            "assistant": {"background_color": "#F3F4F6", "text_color": "#111827", "avatar_size": "small", "border_color": None, "thinking_border_gradient": ["#4F46E5", "#EC4899"]},
            "user": {"background_color": "#4F46E5", "text_color": "#FFFFFF", "border_color": None},
        },
        "input": {"text_color": "#111827", "placeholder_color": "#9CA3AF", "background_color": "#FFFFFF", "border_color": "#E5E7EB", "send_button": {"icon_color": "#4F46E5"}},
        "product_card": {"discount_price_color": "#DC2626"},
        "font": {"ios": {"asset_url": f"{BASE}/font.ttf", "sha256": "0" * 64, "format": "ttf"}},
    },
}


def seed():
    history.clear()
    submissions.clear()
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": "m_seed",
        "role": "assistant",
        "parts": [
            rich("p_intro", "Please fill one of the forms below."),
            contact_marker(),
            ticket_marker(),
            custom_marker(),
        ],
        "created_at": iso(now),
    })


def latest_actionable_parts():
    """Only the newest assistant message's actionable parts are valid — matching the real API."""
    for msg in reversed(history):
        if msg.get("role") != "assistant":
            continue
        return [
            p for p in msg.get("parts", [])
            if p.get("type") in ("show_contact_form", "show_support_ticket", "show_form")
        ]
    return []


def log(event, **kw):
    os.makedirs(os.path.dirname(EVIDENCE), exist_ok=True)
    with open(EVIDENCE, "a") as f:
        f.write(json.dumps({"ts": time.time(), "event": event, **kw}) + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _bytes(self, code, data, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        if path.endswith("/api/v1/chat/config"):
            return self._json(200, CONFIG)
        if path.endswith("/api/v1/chat/messages"):
            return self._json(200, {"messages": list(reversed(history)), "next_cursor": None})
        if path.endswith("/avatar.png") or path.endswith("/logo.png"):
            return self._bytes(200, png(64, 64, (79, 70, 229)), "image/png")
        if path.endswith("/font.ttf"):
            return self._bytes(200, b"", "font/ttf")
        self._json(404, {"error": {"code": "not_found", "message": path}})

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            return self._json(400, {"error": {"code": "validation", "message": "bad json"}})

        if path.endswith("/__control"):
            return self._control(body)

        if path.endswith("/api/v1/chat/actions"):
            return self._actions(body)

        if path.endswith("/api/v1/chat/messages"):
            return self._send(body)

        self._json(404, {"error": {"code": "not_found", "message": path}})

    def _control(self, body):
        """UI-test hooks: {"reset": true} reseeds with fresh part ids; {"fail_next_action": true}
        makes the next POST /actions fail with 500 once."""
        if body.get("reset"):
            state["run"] = uuid.uuid4().hex[:6]
            state["fail_next_action"] = False
            seed()
        if "fail_next_action" in body:
            state["fail_next_action"] = bool(body["fail_next_action"])
        log("control", **body, run=state["run"])
        return self._json(200, {"run": state["run"], "fail_next_action": state["fail_next_action"]})

    def _actions(self, body):
        part_id = body.get("part_id")
        action = body.get("action") or {}
        actionable = latest_actionable_parts()
        match = next((p for p in actionable if p.get("part_id") == part_id), None)
        summary = {k: (f"<{len(v)} attachments>" if k == "attachments" else
                       ({fk: f"<{fv.get('mime_type')} {len(fv.get('data_base64', ''))}b64 {fv.get('filename')}>" for fk, fv in v.items()} if k == "files" else v))
                   for k, v in action.items()}
        log("action", part_id=part_id, action=summary, matched=bool(match), fail_injected=state["fail_next_action"])

        if state["fail_next_action"]:
            state["fail_next_action"] = False
            return self._json(500, {"error": {"code": "internal", "message": "injected failure"}})

        if not part_id or not action:
            return self._json(400, {"error": {"code": "validation", "message": "part_id and action required"}})
        if not match:
            return self._json(409, {"error": {"code": "conflict", "message": "part_id is not the latest actionable part"}})

        atype = action.get("type")
        expected = {
            "show_contact_form": "contact_form",
            "show_support_ticket": "support_ticket",
            "show_form": "form_submission",
        }.get(match.get("type"))
        if atype != expected:
            return self._json(400, {"error": {"code": "validation", "message": f"expected {expected}"}})

        submissions.append({"part_id": part_id, "action": action})
        confirmation = {
            "contact_form": "Thanks, we have received your message.",
            "support_ticket": "Your ticket has been created.",
            "form_submission": "Thanks — your lead is in.",
        }.get(atype, "Thanks!")
        return self._json(200, {
            "submission_id": f"sub_{uuid.uuid4().hex[:8]}",
            "confirmation_text": confirmation,
        })

    def _send(self, body):
        parts = (body.get("message") or {}).get("parts") or []
        now = datetime.now(timezone.utc)
        history.append({
            "message_id": f"u_{len(history)}",
            "role": "user",
            "parts": [rich(f"u{len(history)}", p.get("text", "")) if p.get("type") == "text" else p for p in parts],
            "created_at": iso(now),
        })
        text = " ".join(p.get("text", "") for p in parts if p.get("type") == "text").lower()
        reply_parts = [rich(f"a{len(history)}", "Noted.")]
        if "form" in text:
            # A fresh contact form in the newest reply: the seeded ones become read-only.
            reply_parts = [rich(f"a{len(history)}", "Here is a fresh form."),
                           contact_marker(f"part_contact_{state['run']}_live{len(history)}")]
        reply = {
            "message_id": f"a_{len(history)}",
            "role": "assistant",
            "parts": reply_parts,
            "created_at": iso(now),
        }
        history.append(reply)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        def sse(event, data):
            self.wfile.write(f"event: {event}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()
        sse("status", {"status": "connected"})
        sse("status", {"status": "processing"})
        for part in reply["parts"]:
            sse("part", {"part": part})
        sse("done", {"message": reply})


if __name__ == "__main__":
    seed()
    print(f"forms stand-in on {BASE}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
