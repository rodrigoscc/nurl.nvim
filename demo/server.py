"""A small mock API for the demo, answering like a real one: JSON bodies, a few
status codes and some latency. Hosts starting with "dev." answer as the
development environment.

Run it alone to try requests against it: python3 demo/server.py
"""

import json
import random
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

USERS = [
    {
        "id": 1,
        "name": "Ada Lovelace",
        "email": "ada@example.com",
        "role": "admin",
        "active": False,
        "company": {"name": "Analytical Engines", "city": "London"},
    },
    {
        "id": 2,
        "name": "Grace Hopper",
        "email": "grace@example.com",
        "role": "admin",
        "active": True,
        "company": {"name": "Compilers Inc.", "city": "Arlington"},
    },
    {
        "id": 3,
        "name": "Alan Turing",
        "email": "alan@example.com",
        "role": "member",
        "active": True,
        "company": {"name": "Bletchley Labs", "city": "Milton Keynes"},
    },
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "nginx/1.27.2"
    sys_version = ""

    def log_message(self, *args):
        pass

    def environment(self):
        host = self.headers.get("Host", "")
        return "development" if host.startswith("dev.") else "production"

    def reply(self, status, body):
        # Some latency, like a real API has.
        time.sleep(random.uniform(0.18, 0.35))
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Request-Id", "req_%06x" % random.randrange(16**6))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urlparse(self.path)
        query = parse_qs(url.query)
        parts = [part for part in url.path.split("/") if part]

        if parts == ["users"]:
            role = query.get("role", [None])[0]
            limit = int(query.get("limit", ["10"])[0])
            users = [u for u in USERS if role is None or u["role"] == role]
            users = users[:limit]
            return self.reply(
                200,
                {
                    "environment": self.environment(),
                    "count": len(users),
                    "users": users,
                },
            )
        if len(parts) == 2 and parts[0] == "users":
            for user in USERS:
                if str(user["id"]) == parts[1]:
                    return self.reply(200, user)
            return self.reply(404, {"error": "user not found"})
        if len(parts) == 2 and parts[0] == "orders":
            return self.reply(404, {"error": "order %s not found" % parts[1]})
        if parts == ["reports"]:
            return self.reply(500, {"error": "report service unavailable"})
        return self.reply(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        parts = [part for part in urlparse(self.path).path.split("/") if part]

        if parts == ["posts"]:
            return self.reply(
                201, {"id": 101, **body, "createdAt": "2026-09-29T10:15:00Z"}
            )
        return self.reply(404, {"error": "not found"})


def serve(port=0):
    """Serve in a background thread, on a free port unless one is given."""
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


if __name__ == "__main__":
    server = serve(18080)
    print("Serving on http://127.0.0.1:%d" % server.server_address[1])
    threading.Event().wait()
