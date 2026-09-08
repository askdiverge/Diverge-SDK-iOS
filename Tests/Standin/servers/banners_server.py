#!/usr/bin/env python3
"""Local stand-in for in-chat banners — GET /api/v1/chat/banners?url=.

Mirrors visitor banner filtering: url_pattern substring match, then is_default
fallback. Disabled / empty list via /__control. CTA is an absolute http URL so
Sample onOpenLink / SAMPLE_STANDIN can record it.
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/banners-evidence.jsonl")

history = []
state = {
    "run": uuid.uuid4().hex[:6],
    "banners_empty": False,
    "banner_hits": [],
}

CTA_URL = f"{BASE}/promo/sale"


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


# Catalog rows — filter on each request (same idea as the real API).
BANNER_ROWS = [
    {
        "id": "10",
        "message": "Free shipping on PDP",
        "url_pattern": "/products",
        "is_default": False,
        "is_enabled": True,
        "background_color": "#4F46E5",
        "text_color": "#FFFFFF",
        "cta_url": CTA_URL,
        "cta_label": "Shop sale",
        "cta_style": "button",
        "dismissible": True,
        "sort_order": 1,
    },
    {
        "id": "20",
        "message": "Welcome offer — sitewide",
        "url_pattern": None,
        "is_default": True,
        "is_enabled": True,
        "background_color": "#111827",
        "text_color": "#F9FAFB",
        "cta_url": CTA_URL,
        "cta_label": "See offer",
        "cta_style": "link",
        "dismissible": True,
        "sort_order": 2,
    },
    {
        "id": "99",
        "message": "Disabled — must not show",
        "url_pattern": None,
        "is_default": False,
        "is_enabled": False,
        "background_color": "#FF0000",
        "text_color": "#FFFFFF",
        "cta_url": None,
        "cta_label": None,
        "cta_style": None,
        "dismissible": False,
        "sort_order": 99,
    },
]


def to_chat_banner(row):
    return {
        "id": row["id"],
        "message": row["message"],
        "background_color": row.get("background_color"),
        "text_color": row.get("text_color"),
        "cta_url": row.get("cta_url"),
        "cta_label": row.get("cta_label"),
        "cta_style": row.get("cta_style"),
        "dismissible": row.get("dismissible") is True,
    }


def filter_banners(url):
    if state.get("banners_empty"):
        return []
    page = url or ""
    enabled = [b for b in BANNER_ROWS if b.get("is_enabled")]
    # Null pattern matches any page; patterned requires substring; defaults only as fallback.
    matched = []
    for b in enabled:
        if b.get("is_default"):
            continue
        pattern = b.get("url_pattern")
        if pattern is None or (page and pattern in page):
            matched.append(b)
    if not matched:
        matched = [b for b in enabled if b.get("is_default")]
    matched.sort(key=lambda b: (b.get("sort_order", 0), b["id"]))
    return [to_chat_banner(b) for b in matched]


def config():
    return {
        "display": {
            "name": "Stand-in bot",
            "avatar": {"url": f"{BASE}/avatar.png"},
            "welcome_message": "Local stand-in — in-chat banners.",
            "subtitle": {"text": "Banner stand-in", "link": None},
            "privacy_policy_url": "https://example.com/privacy",
        },
        "theme": THEME,
        "start_prompts": [],
        "popup_messages": [],
    }


def seed():
    history.clear()
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": f"msg_welcome_{state['run']}",
        "role": "assistant",
        "created_at": iso(now),
        "parts": [rich(f"part_welcome_{state['run']}", "Local stand-in — in-chat banners.")],
    })


def evidence(obj):
    with open(EVIDENCE, "a") as f:
        f.write(json.dumps({"ts": time.time(), **obj}) + "\n")


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
        if path == "/api/v1/chat/banners":
            qs = parse_qs(parsed.query)
            url = (qs.get("url") or [None])[0]
            auth = self.headers.get("Authorization", "")
            banners = filter_banners(url)
            hit = {"auth": auth, "url": url, "count": len(banners), "ids": [b["id"] for b in banners]}
            state["banner_hits"].append(hit)
            evidence({"event": "banners", **hit})
            return self._json(200, {"banners": banners})
        if path.startswith("/promo/"):
            return self._json(200, {"ok": True, "path": path})
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
                state["banner_hits"] = []
                state["banners_empty"] = False
                seed()
            if "banners_empty" in body:
                state["banners_empty"] = bool(body["banners_empty"])
            return self._json(200, {
                "run": state["run"],
                "banner_hits": state["banner_hits"],
                "banners_empty": state["banners_empty"],
            })
        if path == "/api/v1/chat/messages":
            # Minimal SSE so a send does not brick the sample if tapped.
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            done = {"message": {
                "message_id": f"msg_{uuid.uuid4().hex[:8]}",
                "role": "assistant",
                "created_at": iso(),
                "parts": [rich("p1", "Noted.")],
            }}
            try:
                self.wfile.write(b'event: status\ndata: {"status":"connected"}\n\n')
                self.wfile.write(f"event: done\ndata: {json.dumps(done)}\n\n".encode())
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        self._empty(404)


if __name__ == "__main__":
    seed()
    print(f"banners_server listening on {BASE}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
