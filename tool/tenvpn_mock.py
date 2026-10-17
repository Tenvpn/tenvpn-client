"""Mock of GET /api/app/v1/awg (docs/api.md). Usage: python -I awg_mock.py <conf> <token> [port]"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

conf_path, token = sys.argv[1], sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 18787
mode = {"status": 200}

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/mode/"):
            mode["status"] = int(self.path.rsplit("/", 1)[1])
            return self._send(200, {"mode": mode["status"]})
        if self.path != "/api/app/v1/awg":
            return self._send(404, {"error": "not_found"})
        if self.headers.get("Authorization") != f"Bearer {token}":
            return self._send(401, {"error": "unauthorized"})
        if mode["status"] != 200:
            return self._send(mode["status"], {"error": "mock"})
        self._send(200, {"version": 1, "name": "🛡 Запасное подключение", "protocol": "2.0",
                         "conf": open(conf_path, encoding="utf-8").read(),
                         "updated_at": "2026-10-17T07:00:00Z"})
    def _send(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.command, " ".join(str(a) for a in args[:2])))

HTTPServer(("127.0.0.1", port), H).serve_forever()
