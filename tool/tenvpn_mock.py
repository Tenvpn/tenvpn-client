"""Mock of the TENVPN app API (docs/api.md): AmneziaWG, account, telemetry.

    python tool/tenvpn_mock.py --token <token> [--awg-conf awg.conf] [--port 18787]
    adb reverse tcp:18787 tcp:18787

Control (no auth, loopback only):
    GET /mock/account?days_left=2&balance=14&status=active&devices=2
    GET /mock/awg/<status>      answer /awg with that HTTP status (200 = normal)
    GET /mock/telemetry         events received so far
"""
import argparse
import datetime
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TELEMETRY_FIELDS = {"version", "event", "app_version", "platform", "os_version", "protocol"}
DAILY_RATE, EXTRA_DEVICE = 7.0, 2.0

parser = argparse.ArgumentParser()
parser.add_argument("--token", required=True)
parser.add_argument("--awg-conf")
parser.add_argument("--port", type=int, default=18787)
args = parser.parse_args()

state = {"awg_status": 200, "balance": 91.0, "status": "active", "devices": 2, "days_left": None}
telemetry = []


def daily_rate(devices):
    return DAILY_RATE + max(0, devices - 2) * EXTRA_DEVICE


def account():
    rate = daily_rate(state["devices"])
    days = state["days_left"]
    if days is None:
        days = int(state["balance"] // rate)
    today = datetime.date.today()
    return {
        "version": 1,
        "balance_rub": state["balance"],
        "daily_rate_rub": rate,
        "days_left": days,
        "paid_until": (today + datetime.timedelta(days=days)).isoformat(),
        "devices": {"active": state["devices"]},
        "status": state["status"],
        "renew_url": "https://t.me/Tenvpnrobot?start=src_app",
        "support_url": "https://t.me/tenvpnsupp",
    }


class Handler(BaseHTTPRequestHandler):
    def _authorized(self):
        return self.headers.get("Authorization") == f"Bearer {args.token}"

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/mock/account":
            q = {k: v[-1] for k, v in parse_qs(url.query).items()}
            if "days_left" in q:
                state["days_left"] = int(q["days_left"])
            if "balance" in q:
                state["balance"] = float(q["balance"])
                state["days_left"] = None if "days_left" not in q else state["days_left"]
            if "status" in q:
                state["status"] = q["status"]
            if "devices" in q:
                state["devices"] = int(q["devices"])
            return self._send(200, account())
        if url.path.startswith("/mock/awg/"):
            state["awg_status"] = int(url.path.rsplit("/", 1)[1])
            return self._send(200, {"awg_status": state["awg_status"]})
        if url.path == "/mock/telemetry":
            return self._send(200, telemetry)
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        if url.path == "/api/app/v1/account":
            return self._send(200, account())
        if url.path == "/api/app/v1/awg":
            if not args.awg_conf:
                return self._send(404, {"error": "awg_disabled"})
            if state["awg_status"] != 200:
                return self._send(state["awg_status"], {"error": "mock"})
            with open(args.awg_conf, encoding="utf-8") as f:
                conf = f.read()
            return self._send(200, {"version": 1, "name": "🛡 Запасное подключение",
                                    "protocol": "2.0", "conf": conf,
                                    "updated_at": "2026-10-17T07:00:00Z"})
        return self._send(404, {"error": "not_found"})

    def do_POST(self):
        if urlparse(self.path).path != "/api/app/v1/telemetry":
            return self._send(404, {"error": "not_found"})
        if not self._authorized():
            return self._send(401, {"error": "unauthorized"})
        length = int(self.headers.get("Content-Length") or 0)
        try:
            event = json.loads(self.rfile.read(length))
        except ValueError:
            return self._send(400, {"error": "bad_json"})
        if not isinstance(event, dict) or set(event) != TELEMETRY_FIELDS:
            return self._send(400, {"error": "unexpected_fields"})
        telemetry.append(event)
        self.send_response(204)
        self.end_headers()

    def _send(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *a):
        sys.stderr.write("%s %s\n" % (self.command, " ".join(str(x) for x in a[:2])))


HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
