#!/usr/bin/env python3
"""Local stand-in for the Chatbot API, focused on the send-photo path.

Mirrors the shapes in specs/chatbot-api.tsp and the behaviour of
apps/api/src/chatbot-api/features/messages/message-structured-part.ts for a visitor's own image
part: history re-serves it as `data:<mime>;base64,<data>` with `caption` only when a filename was
sent. POST /messages logs exactly what arrived (part types, filename presence, mime, decoded size,
pixel size, whether an EXIF APP1 segment survived) and the assistant "describes" the image so the
reply proves the bytes were received. Nothing here is the real API.
"""
import base64, json, os, struct, sys, time, zlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler
from standin_http import serve
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/photo-evidence.jsonl")
history = []  # oldest first; served newest first
turn = 0


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def png(w, h, rgb):
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    rows = b"".join(bytes([0]) + bytes(rgb) * w for _ in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def jpeg_info(data):
    """(width, height, has_exif_app1) from a JPEG byte string, or None."""
    if data[:2] != b"\xff\xd8":
        return None
    i, has_exif, size = 2, False, None
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        seg_len = struct.unpack(">H", data[i + 2:i + 4])[0]
        if marker == 0xE1 and data[i + 4:i + 10] == b"Exif\x00\x00":
            has_exif = True
        if marker in (0xC0, 0xC1, 0xC2) and size is None:
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            size = (w, h)
        if marker == 0xDA:
            break
        i += 2 + seg_len
    return (size[0], size[1], has_exif) if size else None


def rich(part_id, text):
    return {"type": "rich_text", "part_id": part_id, "blocks": [{"type": "paragraph", "spans": [{"type": "text", "text": text}]}]}


def user_history_part(part):
    """message-structured-part.ts: image input -> data URL, caption only from filename."""
    if part.get("type") == "image":
        out = {"type": "image", "url": f"data:{part['mime']};base64,{part['data']}"}
        if part.get("filename"):
            out["caption"] = part["filename"]
        return out
    if part.get("type") == "text":
        return rich(f"u{len(history)}", part["text"])
    return part


CONFIG = {
    "display": {
        "name": "Stand-in bot",
        "avatar": {"url": f"{BASE}/avatar.png"},
        "welcome_message": "Local stand-in — attach a photo and I will describe what arrived.",
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
            self._log(f"history -> {len(history)} messages")
            return self._json({"messages": list(reversed(history)), "next_cursor": None})
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
        payload = json.loads(body)
        parts = payload["message"]["parts"]
        summary = []
        for part in parts:
            if part.get("type") == "image":
                raw = base64.b64decode(part["data"])
                info = jpeg_info(raw)
                summary.append({
                    "type": "image", "mime": part.get("mime"), "filename_present": "filename" in part,
                    "filename": part.get("filename"), "base64_length": len(part["data"]), "decoded_bytes": len(raw),
                    "pixels": f"{info[0]}x{info[1]}" if info else None, "exif_app1_present": info[2] if info else None,
                })
            else:
                summary.append({"type": part.get("type"), "text": part.get("text")})
        record = {"turn": turn, "authorization": self.headers.get("Authorization"), "context": payload.get("context"), "parts": summary}
        with open(EVIDENCE, "a") as f:
            f.write(json.dumps(record) + "\n")
        self._log(f"send #{turn} parts={json.dumps(summary)}")

        now = datetime.now(timezone.utc)
        history.append({"message_id": f"u{turn}", "role": "user", "created_at": iso(now), "parts": [user_history_part(p) for p in parts]})

        images = [s for s in summary if s["type"] == "image"]
        if images:
            img = images[0]
            text = (f"Reply #{turn}: I received your photo — a {img['pixels']} {img['mime']} of {img['decoded_bytes'] // 1024} KB"
                    f"{', no EXIF' if img['exif_app1_present'] is False else ''}"
                    f"{', no filename' if not img['filename_present'] else ', named ' + str(img['filename'])}. "
                    f"{'(' + str(len(images)) + ' images arrived; the AI only sees the first.)' if len(images) > 1 else ''}")
        else:
            text = f"Reply #{turn}: text only, no photo attached."

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        def ev(name, data):
            self.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n".encode())
            self.wfile.flush()

        pid = f"t{turn}p1"
        ev("status", {"status": "connected"})
        ev("status", {"status": "processing"})
        ev("part_delta", {"part_id": pid, "delta": {"action": "start_part", "part_type": "rich_text"}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "start_block", "block_index": 0, "block_type": "paragraph"}})
        for word in text.split(" "):
            ev("part_delta", {"part_id": pid, "delta": {"action": "append_text", "block_index": 0, "text": word + " "}})
            time.sleep(0.03)
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_block", "block_index": 0}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_part"}})
        ev("part", {"part": rich(pid, text)})
        reply = {"message_id": f"t{turn}", "role": "assistant", "created_at": iso(datetime.now(timezone.utc)), "parts": [rich(pid, text)]}
        history.append(reply)
        done = {"message": reply}
        if not (self.headers.get("Authorization") or "").startswith("Bearer bound-"):
            done["visitor_token"] = f"bound-{turn}.{int(time.time())}"
        ev("done", done)


if __name__ == "__main__":
    open(EVIDENCE, "w").close()
    serve(Handler, PORT, f"stand-in chatbot API (send-photo) on {BASE}; evidence -> {EVIDENCE}")
