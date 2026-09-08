#!/usr/bin/env python3
"""Local stand-in for start-prompt chips — GET /api/v1/chat/config.start_prompts.

Welcome-only history by default. Config includes global and patterned prompts.
Text sends get a short reply.

`{{quick_replies}}` is not stripped here. A stored leak and an optional live SSE
part keep the marker so device tests can document that the SDK paints whatever
the API stored. The converter strip lives in parse-token.ts (API unit tests).
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/start-prompts-evidence.jsonl")
history = []
state = {
    "run": uuid.uuid4().hex[:6],
    "emit_quick_replies_leak": False,
    "live_quick_replies": False,
}


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


START_PROMPTS = [
    {"prompt_text": "Track my order", "url_pattern": None},
    {"prompt_text": "Find a size", "url_pattern": "/products"},
    {"prompt_text": "Checkout help", "url_pattern": "/cart"},
]


CONFIG = {
    "display": {
        "name": "Stand-in bot",
        "avatar": {"url": f"{BASE}/avatar.png"},
        "welcome_message": "Local stand-in — tap a starter chip to begin.",
        "subtitle": {"text": "Start-prompt stand-in", "link": None},
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
    "start_prompts": START_PROMPTS,
    "popup_messages": [],
}


def seed_user_history():
    # History user turns must be rich_text — wire `type: text` decodes as `.unknown`
    # and the provider drops the turn (live send uses a local echo instead).
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": f"msg_user_{state['run']}",
        "role": "user",
        "created_at": iso(now),
        "parts": [rich(f"part_user_{state['run']}", "hello from history")],
    })


def seed():
    history.clear()
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": f"msg_welcome_{state['run']}",
        "role": "assistant",
        "created_at": iso(now),
        "parts": [rich(f"part_welcome_{state['run']}", "Tap a chip below, or say hello.")],
    })
    if state["emit_quick_replies_leak"]:
        # Already-persisted rich_text that still contains the marker. The SDK
        # paints this as text; it does not strip and does not create chips.
        history.append({
            "message_id": f"msg_qr_{state['run']}",
            "role": "assistant",
            "created_at": iso(now),
            "parts": [rich(
                f"part_qr_{state['run']}",
                'What next? {{quick_replies:["Dry","Oily"]}} Thanks',
            )],
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
        sys.stderr.write(f'{self.client_address[0]} - "{self.command} {self.path}" {args[1] if len(args) > 1 else ""}\n')

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

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/v1/chat/config":
            return self._json(200, CONFIG)
        if path == "/api/v1/chat/messages":
            return self._json(200, {"messages": list(reversed(history)), "next_cursor": None, "has_more": False})
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
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else {}

        if path == "/__control":
            if body.get("reset") or body.get("seed_user_history"):
                state["run"] = uuid.uuid4().hex[:6]
                state["emit_quick_replies_leak"] = bool(body.get("emit_quick_replies_leak"))
                state["live_quick_replies"] = bool(body.get("live_quick_replies"))
                seed()
                if body.get("seed_user_history"):
                    seed_user_history()
                evidence({
                    "event": "control",
                    "reset": True,
                    "run": state["run"],
                    "emit_quick_replies_leak": state["emit_quick_replies_leak"],
                    "live_quick_replies": state["live_quick_replies"],
                    "seed_user_history": bool(body.get("seed_user_history")),
                })
                return self._json(200, {"ok": True, "run": state["run"]})
            return self._json(400, {"error": "unknown control"})

        if path == "/api/v1/chat/messages":
            text = ""
            parts = (body.get("message") or {}).get("parts") or []
            for part in parts:
                if part.get("type") == "text":
                    text = part.get("text") or ""
            evidence({"event": "send", "text": text, "run": state["run"]})
            now = datetime.now(timezone.utc)
            history.append({
                "message_id": f"msg_user_{uuid.uuid4().hex[:8]}",
                "role": "user",
                "created_at": iso(now),
                "parts": [{"type": "text", "part_id": f"part_user_{uuid.uuid4().hex[:8]}", "text": text}],
            })
            reply_text = f"Noted: {text}" if text else "Noted."
            if state["live_quick_replies"]:
                reply_text = f'{reply_text} {{{{quick_replies:["Dry","Oily"]}}}}'
            reply_part = rich(f"part_bot_{uuid.uuid4().hex[:8]}", reply_text)
            reply = {
                "message_id": f"msg_bot_{uuid.uuid4().hex[:8]}",
                "role": "assistant",
                "created_at": iso(now),
                "parts": [reply_part],
            }
            history.append(reply)
            return sse(self, [
                ("status", {"status": "connected"}),
                ("status", {"status": "processing"}),
                ("part", {"part": reply_part}),
                ("done", {"message": reply}),
            ])

        self._empty(404)


if __name__ == "__main__":
    seed()
    print(f"start-prompts stand-in on http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
