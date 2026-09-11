#!/usr/bin/env python3
"""Local stand-in for the `request_image_upload` marker path.

Seeds one assistant history message that carries the marker (so the card is on screen
at open), and on a text send streams a fresh marker beside a short reply. An image send
is acknowledged like photo_server.py so the CTA → chip → send path can be exercised end
to end. Nothing here is the real API.
"""
import base64, json, os, struct, sys, time, zlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler
from standin_http import serve
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "3000"))
TAIL_DELAY = float(os.environ.get("TAIL_DELAY", "0"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/upload-prompt-evidence.jsonl")
history = []
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


def rich(part_id, text):
    return {"type": "rich_text", "part_id": part_id, "blocks": [{"type": "paragraph", "spans": [{"type": "text", "text": text}]}]}


def upload_marker(part_id):
    return {
        "type": "request_image_upload",
        "part_id": part_id,
        "accepted_types": ["image/png", "image/jpeg", "image/webp"],
        "max_size_bytes": 5_242_880,
    }


def user_history_part(part):
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
        "welcome_message": "Local stand-in — the upload prompt should appear below.",
        "subtitle": {"text": "Upload-prompt stand-in", "link": None},
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

def seed_history():
    """Fresh seed for open / relaunch. `SEED_MARKER_ONLY=1` adds a dropped-at-ingestion row."""
    global history, turn
    history = []
    turn = 0
    seed_now = datetime.now(timezone.utc)
    history.append({
        "message_id": "seed_1",
        "role": "assistant",
        "created_at": iso(seed_now),
        "parts": [
            rich("seed_text", "Please upload a photo of your receipt."),
            upload_marker("seed_upload"),
        ],
    })
    # Marker-only assistant message between the seed and a trailing text — with
    # attachments disabled the SDK must drop it entirely (no empty row between the two).
    if os.environ.get("SEED_MARKER_ONLY") == "1":
        history.append({
            "message_id": "seed_2",
            "role": "assistant",
            "created_at": iso(seed_now),
            "parts": [upload_marker("seed_upload_only")],
        })
        history.append({
            "message_id": "seed_3",
            "role": "assistant",
            "created_at": iso(seed_now),
            "parts": [rich("seed_after", "Trailing note after the marker-only message.")],
        })


seed_history()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _log(self, note=""):
        print(f"[{time.strftime('%H:%M:%S')}] {self.command} {self.path}  {note}", flush=True)

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
            with open(EVIDENCE, "a") as f:
                f.write(json.dumps({"event": "history", "count": len(history)}) + "\n")
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
        if url.path == "/__control":
            payload = json.loads(body) if body else {}
            if payload.get("reset"):
                seed_history()
                self._log("reset")
                return self._json({"ok": True})
            return self._json({"error": "unknown control"}, 400)
        if url.path != "/api/v1/chat/messages":
            self._log("404")
            return self._json({"error": "not_found"}, 404)

        turn += 1
        payload = json.loads(body)
        parts_in = payload["message"]["parts"]
        text_in = next((p.get("text") for p in parts_in if p.get("type") == "text"), "")
        images = [p for p in parts_in if p.get("type") == "image"]
        self._log(f"send #{turn} text={text_in!r} images={len(images)}")
        with open(EVIDENCE, "a") as f:
            f.write(json.dumps({
                "event": "send",
                "turn": turn,
                "text": text_in,
                "image_count": len(images),
                "mimes": [p.get("mime") for p in images],
                "filenames": [p.get("filename") for p in images],
            }) + "\n")

        now = datetime.now(timezone.utc)
        history.append({
            "message_id": f"u{turn}",
            "role": "user",
            "created_at": iso(now),
            "parts": [user_history_part(p) for p in parts_in],
        })

        if images:
            reply_text = f"I received your photo (turn #{turn})."
            reply_parts = [rich(f"t{turn}p1", reply_text)]
        else:
            reply_text = f"Reply #{turn}: please add a photo."
            reply_parts = [rich(f"t{turn}p1", reply_text), upload_marker(f"t{turn}upload")]

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
        ev("part_delta", {"part_id": pid, "delta": {"action": "start_part", "part_type": "rich_text"}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "start_block", "block_index": 0, "block_type": "paragraph"}})
        for word in reply_text.split(" "):
            ev("part_delta", {"part_id": pid, "delta": {"action": "append_text", "block_index": 0, "text": word + " "}})
            time.sleep(0.02)
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_block", "block_index": 0}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_part"}})
        for part in reply_parts:
            ev("part", {"part": part})
        # Hold the stream open after the marker so the UI test can observe the card disabled
        # while streamingTurnID is set, then enabled once `done` lands.
        if not images and TAIL_DELAY > 0:
            self._log(f"holding stream {TAIL_DELAY}s before done")
            time.sleep(TAIL_DELAY)
        reply = {
            "message_id": f"t{turn}",
            "role": "assistant",
            "created_at": iso(datetime.now(timezone.utc)),
            "parts": reply_parts,
        }
        history.append(reply)
        ev("done", {"message": reply})


if __name__ == "__main__":
    with open(EVIDENCE, "w") as f:
        f.write(json.dumps({"seed": "request_image_upload"}) + "\n")
    serve(Handler, PORT,
          f"stand-in chatbot API (upload prompt) on http://127.0.0.1:{PORT}; evidence -> {EVIDENCE}")
