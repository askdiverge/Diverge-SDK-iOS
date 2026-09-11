#!/usr/bin/env python3
"""Local stand-in for GDPR export — GET /api/v1/chat/export.

POST /__control can inject export_status (200 / 401 / 500) for XCUITests.
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler
from standin_http import serve
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/export-evidence.jsonl")

history = []
state = {
    "run": uuid.uuid4().hex[:6],
    "export_status": 200,
    "export_delay_ms": 0,
    "export_hits": [],
}


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


THEME = {
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
}


def config():
    return {
        "display": {
            "name": "Stand-in bot",
            "avatar": {"url": f"{BASE}/avatar.png"},
            "welcome_message": "Local stand-in — download my data.",
            "subtitle": {"text": "Export stand-in", "link": None},
            "privacy_policy_url": "https://example.com/privacy",
        },
        "theme": THEME,
        "dark_theme": THEME,
        "product_card": {"open_label": None, "add_to_cart": {"enabled": False}},
        "livechat": {
            "enabled": False,
            "configured": False,
            "availability_status": "offline",
            "availability_reason": "manual_offline",
            "show_livechat_logo": False,
            "attachments_enabled": False,
            "max_attachment_size_bytes": 5242880,
        },
        "popup_messages": [],
    }


def export_body():
    return {
        "generated_at": iso(),
        "chatbot_id": "stand-in-bot",
        "visitor_id": "visitor-export-test",
        "session": {"values": []},
        "conversations": [],
        "livechat_sessions": [],
        "attachments": [],
        "support_tickets": [],
        "webhook_events": [],
    }


def seed():
    history.clear()
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": f"msg_welcome_{state['run']}",
        "role": "assistant",
        "created_at": iso(now),
        "parts": [rich(f"part_welcome_{state['run']}", "Local stand-in — download my data.")],
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
        path = urlparse(self.path).path
        if path == "/api/v1/chat/config":
            return self._json(200, config())
        if path == "/api/v1/chat/messages":
            return self._json(200, {"messages": list(reversed(history)), "next_cursor": None, "has_more": False})
        if path == "/api/v1/chat/export":
            delay = max(0, int(state.get("export_delay_ms") or 0))
            if delay:
                time.sleep(delay / 1000.0)
            auth = self.headers.get("Authorization", "")
            hit = {"auth": auth, "status": state["export_status"], "delay_ms": delay}
            state["export_hits"].append(hit)
            evidence({"event": "export", **hit})
            status = state["export_status"]
            if status == 200:
                return self._json(200, export_body())
            if status == 401:
                return self._json(401, {"error": {"code": "unauthorized", "message": "gone"}})
            return self._json(500, {"error": {"code": "internal", "message": "boom"}})
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
            if body.get("reset"):
                state["run"] = uuid.uuid4().hex[:6]
                state["export_hits"] = []
                state["export_delay_ms"] = 0
            if "export_status" in body:
                state["export_status"] = int(body["export_status"])
            if "export_delay_ms" in body:
                state["export_delay_ms"] = max(0, int(body["export_delay_ms"]))
            seed()
            evidence({"event": "control", "body": body, "run": state["run"]})
            return self._json(200, {
                "ok": True,
                "run": state["run"],
                "export_status": state["export_status"],
                "export_delay_ms": state["export_delay_ms"],
                "export_hits": state["export_hits"],
            })
        if path == "/api/v1/chat/messages":
            text = ""
            for part in body.get("message", {}).get("parts", []):
                if part.get("type") == "text":
                    text = part.get("text", "")
            mid = f"msg_user_{uuid.uuid4().hex[:6]}"
            reply_id = f"msg_bot_{uuid.uuid4().hex[:6]}"
            history.append({"message_id": mid, "role": "user", "created_at": iso(), "parts": [rich(f"part_{mid}", text)]})
            reply = {
                "message_id": reply_id,
                "role": "assistant",
                "created_at": iso(),
                "parts": [rich(f"part_{reply_id}", f"Got: {text}")],
            }
            history.append(reply)
            return sse(self, [
                ("part", {"part": reply["parts"][0]}),
                ("done", {"message": reply, "visitor_token": "visitor-bound-token"}),
            ])
        if path == "/api/v1/chat/rate":
            return self._empty(200)
        self._empty(404)


if __name__ == "__main__":
    seed()
    serve(Handler, PORT, f"export stand-in on {BASE}")
