#!/usr/bin/env python3
"""Local stand-in for dark appearance — light vs dark_theme on /config.

POST /__control can omit dark_theme so XCUITests cover the unconfigured clone path.
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/dark-theme-evidence.jsonl")

history = []
state = {
    "run": uuid.uuid4().hex[:6],
    "include_dark_theme": True,
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


LIGHT_THEME = {
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

# Deliberately near-black so pixel samples are unambiguous vs #FFFFFF.
DARK_THEME = {
    "brand": {"primary_color": "#818CF8"},
    "surface": {"background_color": "#1C1C1E", "muted_text_color": "#9BA1A6"},
    "header": {
        "alignment": "center",
        "logo": {"url": f"{BASE}/logo.png"},
        "button": {"background_color": "#2C2C2E", "icon_color": "#FFFFFF"},
    },
    "messages": {
        "assistant": {
            "background_color": "#2C2C2E",
            "text_color": "#F2F2F7",
            "border_color": "#1C1C1E",
            "thinking_border_gradient": ["#1C1C1E", "#818CF8", "#1C1C1E"],
        },
        "user": {"background_color": "#818CF8", "text_color": "#FFFFFF"},
    },
    "input": {
        "text_color": "#F2F2F7",
        "placeholder_color": "#8E8E93",
        "background_color": "#2C2C2E",
        "border_color": "#3A3A3C",
        "send_button": {"icon_color": "#FFFFFF"},
    },
    "product_card": {"discount_price_color": "#FF6B6B"},
    "font": {"ios": {"asset_url": f"{BASE}/font.ttf", "sha256": "0" * 64, "format": "ttf"}},
}


def config():
    body = {
        "display": {
            "name": "Stand-in bot",
            "avatar": {"url": f"{BASE}/avatar.png"},
            "welcome_message": "Local stand-in — dark appearance.",
            "subtitle": {"text": "Dark theme stand-in", "link": None},
            "privacy_policy_url": "https://example.com/privacy",
        },
        "theme": LIGHT_THEME,
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
    if state["include_dark_theme"]:
        body["dark_theme"] = DARK_THEME
    return body


def seed():
    history.clear()
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": f"msg_welcome_{state['run']}",
        "role": "assistant",
        "created_at": iso(now),
        "parts": [rich(f"part_welcome_{state['run']}", "Local stand-in — dark appearance.")],
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
            if "include_dark_theme" in body:
                state["include_dark_theme"] = bool(body["include_dark_theme"])
            # Flip the booted simulator's appearance from the Mac host (UITests cannot spawn Process).
            if body.get("sim_appearance") in ("light", "dark"):
                udid = body.get("sim_udid") or os.environ.get("SIM_UDID", "booted")
                appearance = body["sim_appearance"]
                os.system(f'xcrun simctl ui {udid} appearance {appearance}')
                evidence({"event": "sim_appearance", "appearance": appearance, "udid": udid})
            seed()
            evidence({"event": "control", "body": body, "run": state["run"]})
            return self._json(200, {"ok": True, "run": state["run"], "include_dark_theme": state["include_dark_theme"]})
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
    print(f"dark theme stand-in on {BASE}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
