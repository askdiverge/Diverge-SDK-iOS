#!/usr/bin/env python3
"""Local stand-in for product card CTAs — open label, splash, add-to-cart.

Seeds history with a products part (splash + add_to_cart.sku). Config exposes
product_card.open_label and product_card.add_to_cart.enabled, both mutable via
POST /__control so device tests can cover the null-label fallback and the cart gate.
"""
import json, os, struct, sys, time, zlib, uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PORT = int(os.environ.get("PORT", "3000"))
BASE = f"http://127.0.0.1:{PORT}"
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/product-actions-evidence.jsonl")
history = []
state = {
    "run": uuid.uuid4().hex[:6],
    "open_label": "Se produkt",
    "add_to_cart_enabled": True,
    "seed_leak": False,
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


def products_part():
    return {
        "type": "products",
        "part_id": f"part_products_{state['run']}",
        "products": [
            {
                "id": "prod_tee",
                "title": "Classic Tee",
                "description": "Soft cotton. No cart marker left in description.",
                "image_url": f"{BASE}/product.png",
                "price": {"amount": 199.0, "currency": "DKK"},
                "original_price": {"amount": 299.0, "currency": "DKK"},
                "splash": "60% Deal",
                "url": f"{BASE}/products/classic-tee",
                "add_to_cart": {"sku": "SKU-TEE-001"},
            },
            {
                "id": "prod_hat",
                "title": "Classic Hat",
                "description": "No sku on this card.",
                "image_url": f"{BASE}/product.png",
                "price": {"amount": 99.0, "currency": "DKK"},
                "url": f"{BASE}/products/classic-hat",
            },
        ],
    }


def config():
    return {
        "display": {
            "name": "Stand-in bot",
            "avatar": {"url": f"{BASE}/avatar.png"},
            "welcome_message": "Local stand-in — product CTAs below.",
            "subtitle": {"text": "Product-actions stand-in", "link": None},
            "privacy_policy_url": "https://example.com/privacy",
        },
        "theme": {
            "brand": {"primary_color": "#4F46E5"},
            "surface": {"background_color": "#FFFFFF", "muted_text_color": "#6B7280"},
            "header": {
                "alignment": "left",
                "logo": {"url": f"{BASE}/logo.png"},
                "button": {"background_color": "#4F46E5", "icon_color": "#FFFFFF"},
            },
            "messages": {
                "assistant": {
                    "background_color": "#F3F4F6",
                    "text_color": "#111827",
                    "avatar_size": "small",
                    "border_color": None,
                    "thinking_border_gradient": ["#4F46E5", "#EC4899"],
                },
                "user": {"background_color": "#4F46E5", "text_color": "#FFFFFF", "border_color": None},
            },
            "input": {
                "text_color": "#111827",
                "placeholder_color": "#9CA3AF",
                "background_color": "#FFFFFF",
                "border_color": "#E5E7EB",
                "send_button": {"icon_color": "#4F46E5"},
            },
            "product_card": {
                "discount_price_color": "#DC2626",
                "button": {"background_color": "#4F46E5", "bold": True},
            },
            "font": {"ios": {"asset_url": f"{BASE}/font.ttf", "sha256": "0" * 64, "format": "ttf"}},
        },
        "product_card": {
            "open_label": state["open_label"],
            "add_to_cart": {"enabled": bool(state["add_to_cart_enabled"])},
        },
        "popup_messages": [],
    }


def seed():
    history.clear()
    now = datetime.now(timezone.utc)
    history.append({
        "message_id": f"msg_welcome_{state['run']}",
        "role": "assistant",
        "created_at": iso(now),
        "parts": [
            rich(f"part_welcome_{state['run']}", "Here are a couple of picks."),
            products_part(),
        ],
    })
    if state["seed_leak"]:
        # Documents that a leaked marker in rich_text is painted as stored by the SDK.
        # Converter strip is API-only (parse-token.ts).
        history.append({
            "message_id": f"msg_leak_{state['run']}",
            "role": "assistant",
            "created_at": iso(now),
            "parts": [rich(
                f"part_leak_{state['run']}",
                "Leaked marker {{add_to_cart:LEAK-SKU}} stays in stored text.",
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
            return self._json(200, config())
        if path == "/api/v1/chat/messages":
            return self._json(200, {"messages": list(reversed(history)), "next_cursor": None, "has_more": False})
        if path in ("/avatar.png", "/logo.png", "/product.png"):
            raw = png(64, 64, (79, 70, 229))
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if path.startswith("/products/"):
            return self._json(200, {"ok": True, "path": path})
        if path == "/font.ttf":
            return self._empty(404)
        self._empty(404)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = json.loads(raw) if raw else {}

        if path == "/__control":
            if body.get("reset") or "open_label" in body or "add_to_cart_enabled" in body:
                state["run"] = uuid.uuid4().hex[:6]
                if "open_label" in body:
                    # Explicit null → use localised fallback on the client.
                    state["open_label"] = body["open_label"]
                if "add_to_cart_enabled" in body:
                    state["add_to_cart_enabled"] = bool(body["add_to_cart_enabled"])
                state["seed_leak"] = bool(body.get("seed_leak"))
                # Default reset keeps current open_label / cart gate unless overridden above.
                if body.get("reset") and "open_label" not in body and "add_to_cart_enabled" not in body:
                    state["open_label"] = "Se produkt"
                    state["add_to_cart_enabled"] = True
                    state["seed_leak"] = bool(body.get("seed_leak"))
                seed()
                evidence({
                    "event": "control",
                    "run": state["run"],
                    "open_label": state["open_label"],
                    "add_to_cart_enabled": state["add_to_cart_enabled"],
                    "seed_leak": state["seed_leak"],
                })
                return self._json(200, {
                    "ok": True,
                    "run": state["run"],
                    "open_label": state["open_label"],
                    "add_to_cart_enabled": state["add_to_cart_enabled"],
                })
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
            reply_part = rich(f"part_bot_{uuid.uuid4().hex[:8]}", f"Noted: {text}" if text else "Noted.")
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
    print(f"product-actions stand-in on http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
