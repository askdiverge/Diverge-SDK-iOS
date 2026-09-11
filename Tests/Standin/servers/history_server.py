#!/usr/bin/env python3
"""Local stand-in for the Chatbot API, focused on reverse pagination.

Seeds TOTAL messages (default 300, alternating user / assistant, chronological ids #000..#299)
and serves them newest-first in pages of PAGE (default 100) with opaque cursors, exactly like
GET /api/v1/chat/messages?cursor=&limit=. Options via env:

  PORT       listen port (3000)
  TOTAL      seeded message count (300)
  PAGE       page size (100) — set small (e.g. 4) to exercise a page shorter than a viewport
  DELAY      seconds to hold every *older* page (cursor != None) so the trigger → prepend window
             is observable from XCUITest (1.5)
  FAIL_ONCE  cursor whose first request answers 500 — the retry path (unset)
  SHAPE      role sequence the seed repeats: "alt" (user, assistant) or "nonalt"
             (user, system, assistant, user, assistant, assistant) — pages whose roles do not
             strictly alternate, so consecutive bots / a system note / a bot-led older page all
             occur. Written as the first evidence line so the UI test can assert render order.
  EVIDENCE   JSONL log of every history call (/tmp/diverge-standin/history-evidence.jsonl)

POST /messages streams a short SSE reply so a send after prepends can be exercised too.
Nothing here is the real API.
"""
import json, os, sys, time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from photo_server import CONFIG, iso, png, rich  # noqa: E402

PORT = int(os.environ.get("PORT", "3000"))
TOTAL = int(os.environ.get("TOTAL", "300"))
PAGE = int(os.environ.get("PAGE", "100"))
DELAY = float(os.environ.get("DELAY", "1.5"))
FAIL_ONCE = os.environ.get("FAIL_ONCE")
SHAPES = {
    "alt": ["user", "assistant"],
    "nonalt": ["user", "system", "assistant", "user", "assistant", "assistant"],
}
SHAPE = SHAPES[os.environ.get("SHAPE", "alt")]
EVIDENCE = os.environ.get("EVIDENCE", "/tmp/diverge-standin/history-evidence.jsonl")

FILLER = [
    "",
    " Short follow-up.",
    " A slightly longer line so rows do not all share one height and the list has to measure.",
    " Two sentences here. The second one wraps on an iPhone so this row is taller than most.",
]

t0 = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
seeded = []  # chronological
for n in range(TOTAL):
    role = SHAPE[n % len(SHAPE)]
    text = f"#{n:03d} {role} message.{FILLER[n % len(FILLER)]}"
    seeded.append({
        "message_id": f"m{n:03d}", "role": role,
        "created_at": iso(t0 + timedelta(minutes=n)),
        "parts": [rich(f"p{n:03d}", text)],
    })
live = []  # messages sent during the run, appended after the seed
failed_once = set()
history_calls = 0
turn = 0


def reset_state():
    """Back to seed: forget live sends, the injected-500 memory, and the evidence log."""
    global history_calls, turn
    live.clear()
    failed_once.clear()
    history_calls = 0
    turn = 0
    with open(EVIDENCE, "w") as f:
        f.write(json.dumps({"shape": SHAPE, "total": TOTAL}) + "\n")


def page_for(cursor):
    """Newest-first slice. cursor None → newest PAGE; cursor 'c<k>' → the k-th older page."""
    k = 0 if cursor is None else int(cursor[1:])
    everything = seeded + live
    end = len(everything) - k * PAGE
    start = max(0, end - PAGE)
    messages = list(reversed(everything[start:end]))
    next_cursor = f"c{k + 1}" if start > 0 else None
    return messages, next_cursor


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
        global history_calls
        url = urlparse(self.path)
        if url.path == "/api/v1/chat/config":
            self._log()
            return self._json(CONFIG)
        if url.path == "/api/v1/chat/messages":
            history_calls += 1
            cursor = parse_qs(url.query).get("cursor", [None])[0]
            limit = parse_qs(url.query).get("limit", [None])[0]
            if cursor is not None:
                with open(EVIDENCE, "a") as f:
                    f.write(json.dumps({"call": history_calls, "cursor": cursor, "phase": "start", "t": time.time()}) + "\n")
                time.sleep(DELAY)
            if FAIL_ONCE and cursor == FAIL_ONCE and cursor not in failed_once:
                failed_once.add(cursor)
                self._log(f"history cursor={cursor} -> 500 (FAIL_ONCE)")
                with open(EVIDENCE, "a") as f:
                    f.write(json.dumps({"call": history_calls, "cursor": cursor, "limit": limit, "status": 500}) + "\n")
                return self._json({"error": "injected"}, 500)
            messages, next_cursor = page_for(cursor)
            ids = f"{messages[-1]['message_id']}..{messages[0]['message_id']}" if messages else "-"
            self._log(f"history cursor={cursor} limit={limit} -> {len(messages)} messages ({ids}) next_cursor={next_cursor}")
            with open(EVIDENCE, "a") as f:
                f.write(json.dumps({"call": history_calls, "cursor": cursor, "limit": limit, "status": 200,
                                    "count": len(messages), "range": ids, "next_cursor": next_cursor}) + "\n")
            return self._json({"messages": messages, "next_cursor": next_cursor})
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
            # `{"reset": true}` returns the run to seed: every flow (topDown / bottomUp) then sees
            # the same pages, call counts and exhaustion point instead of the previous flow's
            # sent messages leaking into the newest page.
            if json.loads(body or b"{}").get("reset"):
                reset_state()
                self._log("control reset")
            return self._json({"ok": True})
        if url.path != "/api/v1/chat/messages":
            self._log("404")
            return self._json({"error": "not_found"}, 404)
        turn += 1
        payload = json.loads(body)
        text_in = next((p.get("text") for p in payload["message"]["parts"] if p.get("type") == "text"), "")
        self._log(f"send #{turn} text={text_in!r}")
        now = datetime.now(timezone.utc)
        live.append({"message_id": f"u{turn}", "role": "user", "created_at": iso(now),
                     "parts": [rich(f"u{turn}", text_in)]})
        text = f"Reply #{turn}: got {text_in!r} after {history_calls} history calls."

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
        for word in text.split(" "):
            ev("part_delta", {"part_id": pid, "delta": {"action": "append_text", "block_index": 0, "text": word + " "}})
            time.sleep(0.03)
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_block", "block_index": 0}})
        ev("part_delta", {"part_id": pid, "delta": {"action": "end_part"}})
        ev("part", {"part": rich(pid, text)})
        reply = {"message_id": f"t{turn}", "role": "assistant", "created_at": iso(datetime.now(timezone.utc)), "parts": [rich(pid, text)]}
        live.append(reply)
        ev("done", {"message": reply})


if __name__ == "__main__":
    reset_state()
    print(f"stand-in chatbot API (history) on http://127.0.0.1:{PORT}; TOTAL={TOTAL} PAGE={PAGE} DELAY={DELAY} "
          f"FAIL_ONCE={FAIL_ONCE} SHAPE={SHAPE}; evidence -> {EVIDENCE}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
