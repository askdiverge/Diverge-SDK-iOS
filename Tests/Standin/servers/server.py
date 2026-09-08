#!/usr/bin/env python3
"""Local stand-in for the Chatbot API, just enough to exercise the iOS SDK's attachment paths.

Serves config, a history page with image + file parts (one already expired), an SSE reply whose
`done` carries image + file parts and a conversation-bound `visitor_token`, and signed attachment
URLs that 401 once their short TTL passes. Logs every Authorization header so token rotation is
visible. Nothing here is the real API — it mirrors specs/chatbot-api.tsp shapes only.
"""
import json, os, struct, sys, time, zlib
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
TTL = int(os.environ.get("ATTACHMENT_TTL", "90"))  # seconds; real API uses 900
turn = 0


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def png(w, h, rgb):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    rows = b""
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            t = x / max(w - 1, 1)
            row += bytes([int(rgb[0] * (1 - t) + 40 * t), int(rgb[1] * (1 - t / 2)), int(rgb[2] * (1 - t) + 200 * t)])
        rows += bytes(row)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


PDF = b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"


def signed(attachment_id, expires_at):
    return f"{BASE}/api/v1/chat/livechat/attachments/{attachment_id}?token={int(expires_at.timestamp())}"


def image_part(attachment_id, caption, expires_at, thumb=True):
    part = {
        "type": "image",
        "attachment_id": attachment_id,
        "url": signed(attachment_id, expires_at),
        "mime_type": "image/png",
        "size_bytes": 14200,
        "url_expires_at": iso(expires_at),
        "caption": caption,
    }
    if thumb:
        part["thumbnail_url"] = signed(attachment_id + "-thumb", expires_at)
    return part


def file_part(attachment_id, filename, expires_at):
    return {
        "type": "file",
        "attachment_id": attachment_id,
        "filename": filename,
        "url": signed(attachment_id, expires_at),
        "mime_type": "application/pdf",
        "size_bytes": 48231,
        "url_expires_at": iso(expires_at),
    }


def rich(part_id, text):
    return {"type": "rich_text", "part_id": part_id, "blocks": [{"type": "paragraph", "spans": [{"type": "text", "text": text}]}]}


CONFIG = {
    "display": {
        "name": "Stand-in bot",
        "avatar": {"url": f"{BASE}/avatar.png"},
        "welcome_message": "Local stand-in — attachments expire after %ds." % TTL,
        "subtitle": {"text": "Local stand-in", "link": None},
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


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _log(self, note=""):
        auth = self.headers.get("Authorization", "-")
        print(f"[{time.strftime('%H:%M:%S')}] {self.command} {self.path}  Authorization: {auth}  {note}", flush=True)

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode())

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/api/v1/chat/config":
            self._log()
            return self._json(CONFIG)
        if url.path == "/api/v1/chat/messages":
            self._log("history")
            now = datetime.now(timezone.utc)
            live = now + timedelta(seconds=TTL)
            gone = now - timedelta(seconds=30)
            return self._json({
                "messages": [  # newest first, as the API pages
                    {"message_id": "h3", "role": "agent", "created_at": iso(now - timedelta(minutes=1)), "parts": [
                        rich("h3p1", "Here is the receipt and the invoice from history."),
                        image_part("hist-receipt", "Receipt from history", live),
                        file_part("hist-invoice", "invoice-history.pdf", live),
                    ]},
                    {"message_id": "h2", "role": "assistant", "created_at": iso(now - timedelta(minutes=20)), "parts": [
                        rich("h2p1", "This one's signed URL already expired 30s ago:"),
                        image_part("old-photo", "Expired photo", gone, thumb=False),
                        file_part("old-file", "expired-terms.pdf", gone),
                    ]},
                    {"message_id": "h1", "role": "user", "created_at": iso(now - timedelta(minutes=21)), "parts": [rich("h1p1", "Can you send me my receipt?")]},
                ],
                "next_cursor": None,
            })
        if url.path.startswith("/api/v1/chat/livechat/attachments/"):
            attachment_id = url.path.rsplit("/", 1)[-1]
            token = parse_qs(url.query).get("token", ["0"])[0]
            if int(token) <= time.time():
                self._log(f"attachment {attachment_id} -> 401 expired")
                return self._json({"error": "attachment_token_expired"}, 401)
            self._log(f"attachment {attachment_id} -> 200")
            if attachment_id.endswith("-thumb"):
                return self._send(200, png(160, 120, (79, 70, 229)), "image/png")
            if "invoice" in attachment_id or "file" in attachment_id or "terms" in attachment_id:
                return self._send(200, PDF, "application/pdf")
            return self._send(200, png(640, 480, (236, 72, 153)), "image/png")
        if url.path in ("/avatar.png", "/logo.png"):
            return self._send(200, png(64, 64, (79, 70, 229)), "image/png")
        if url.path == "/font.ttf":
            return self._send(404, b"no font", "text/plain")
        self._log("404")
        self._json({"error": "not_found"}, 404)

    def do_POST(self):
        global turn
        url = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        if url.path != "/api/v1/chat/messages":
            self._log("404")
            return self._json({"error": "not_found"}, 404)
        turn += 1
        auth = self.headers.get("Authorization", "")
        bound = auth.startswith("Bearer bound-")
        self._log(f"send #{turn} {'(already bound)' if bound else '(unbound -> will rotate)'} body={body.decode(errors='replace')[:80]}")

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        def ev(name, data):
            self.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()

        pid = f"t{turn}p1"
        text = f"Reply #{turn}: your photo and the signed PDF are attached below."
        ev("status", {"status": "connected"})
        ev("status", {"status": "processing"})
        ev("part_delta", {"part_id": pid, "delta": {"action": "start_part", "part_type": "rich_text"}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "start_block", "block_index": 0, "block_type": "paragraph"}})
        for word in text.split(" "):
            ev("part_delta", {"part_id": pid, "delta": {"action": "append_text", "block_index": 0, "text": word + " "}})
            time.sleep(0.05)
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_block", "block_index": 0}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_part"}})
        ev("part", {"part": rich(pid, text)})

        expires = datetime.now(timezone.utc) + timedelta(seconds=TTL)
        done = {"message": {
            "message_id": f"t{turn}", "role": "assistant", "created_at": iso(datetime.now(timezone.utc)),
            "parts": [rich(pid, text), image_part(f"live-photo-{turn}", f"Live photo #{turn}", expires), file_part(f"live-file-{turn}", f"signed-{turn}.pdf", expires)],
        }}
        if not bound:
            done["visitor_token"] = f"bound-{turn}.{int(time.time())}"
        ev("done", done)


if __name__ == "__main__":
    print(f"stand-in chatbot API on {BASE}  (attachment TTL {TTL}s)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
