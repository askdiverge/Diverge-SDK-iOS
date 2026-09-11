"""Shared listener for the stand-in Chatbot API servers."""

import socketserver
from http.server import ThreadingHTTPServer


class StandinHTTPServer(ThreadingHTTPServer):
    """`ThreadingHTTPServer` that is reachable the moment it is bound.

    `HTTPServer.server_bind` calls `socket.getfqdn(host)` — a reverse-DNS lookup
    of 127.0.0.1 — *between* `bind()` and `listen()`. On a CI resolver that PTR
    query can hang for ~30 s, and a socket that is bound but not yet listening
    drops every SYN, so the app's bootstrap sees connect *timeouts* rather than
    refusals — which read like a missing server. The lookup is skipped; the
    name is only ever echoed in headers nothing reads.

    The accept queue is also deepened from the stdlib default of 5: opening the
    chat fires `/config`, `/banners`, `/messages` and the avatar, logo and font
    fetches at once, and an overflowing queue drops SYNs the same way.
    """

    request_queue_size = 128

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def serve(handler, port, banner):
    """Print `banner`, then serve `handler` on 127.0.0.1:`port` until killed."""
    print(banner, flush=True)
    StandinHTTPServer(("127.0.0.1", port), handler).serve_forever()
