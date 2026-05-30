#!/usr/bin/env python3
"""
Shio away-push relay — reference implementation (Phase 6 scaffold).

The one consciously-scoped Shio-operated piece: a thin, opaque relay that
forwards "a session needs you" triggers from your companion to your phone via
APNs. It carries *which session* wants you and nothing else — never code, never
terminal output. It is self-hostable, so sovereignty purists can run their own
and point the app at it (Shio → relay base URL in the App Group default
`shio.relay.baseURL`).

Endpoints (all JSON):
  POST /register        { "deviceToken": "<apns-hex>" }
  POST /activity-token  { "deviceToken", "activityToken", "sessionID" }
  POST /notify          { "deviceToken", "hostId"?, "title"?, "body"? }
        ^ called by the companion away-watcher when an agent blocks/finishes.

RUNTIME/INFRA NOTE: APNs requires an HTTP/2 connection with token-based (JWT
ES256) auth using your APNs key (.p8). This scaffold sends real pushes when
`httpx` + `pyjwt[crypto]` are installed and the APNS_* env vars are set;
otherwise it logs the push it *would* send. Deploy behind TLS. Do not log
payloads in production.

Env for real APNs:
  APNS_KEY_PATH   path to AuthKey_XXXX.p8
  APNS_KEY_ID     the key id (10 chars)
  APNS_TEAM_ID    your Apple team id (10 chars)
  APNS_TOPIC      app bundle id, e.g. sh.shio.app
  APNS_ENV        "sandbox" (default) or "production"
"""

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE_PATH = os.path.expanduser("~/.shio-relay-state.json")


def load_state() -> dict:
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except Exception:
        return {"devices": {}, "activityTokens": {}}


def save_state(state: dict) -> None:
    try:
        with open(STATE_PATH, "w") as f:
            json.dump(state, f)
    except Exception as e:
        print("[relay] could not persist state:", e)


# ---------------------------------------------------------------------------
# APNs

def _apns_jwt() -> str:
    import jwt  # pyjwt[crypto]
    key_path = os.environ["APNS_KEY_PATH"]
    key_id = os.environ["APNS_KEY_ID"]
    team_id = os.environ["APNS_TEAM_ID"]
    with open(key_path) as f:
        key = f.read()
    return jwt.encode(
        {"iss": team_id, "iat": int(time.time())},
        key,
        algorithm="ES256",
        headers={"kid": key_id},
    )


def send_apns(device_token: str, payload: dict) -> None:
    """Send one push. Real send if configured + deps present; else log."""
    topic = os.environ.get("APNS_TOPIC")
    have_creds = all(os.environ.get(k) for k in ("APNS_KEY_PATH", "APNS_KEY_ID", "APNS_TEAM_ID")) and topic
    try:
        import httpx  # provides HTTP/2
    except ImportError:
        httpx = None

    if not (have_creds and httpx):
        print(f"[relay] (dry-run) would push to {device_token[:8]}…: {json.dumps(payload)}")
        print("[relay] configure APNS_* env + install httpx pyjwt[crypto] to send for real.")
        return

    env = os.environ.get("APNS_ENV", "sandbox")
    host = "api.sandbox.push.apple.com" if env == "sandbox" else "api.push.apple.com"
    url = f"https://{host}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {_apns_jwt()}",
        "apns-topic": topic,
        "apns-push-type": "alert",
    }
    try:
        with httpx.Client(http2=True, timeout=10) as client:
            r = client.post(url, headers=headers, content=json.dumps(payload))
            if r.status_code != 200:
                print(f"[relay] APNs rejected ({r.status_code}): {r.text}")
    except Exception as e:
        print("[relay] APNs send failed:", e)


# ---------------------------------------------------------------------------
# HTTP

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _read(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return {}

    def _reply(self, code: int, obj: dict):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        path = self.path.rstrip("/")
        req = self._read()
        state = load_state()

        if path == "/register":
            token = req.get("deviceToken", "")
            if not token:
                return self._reply(400, {"error": "missing deviceToken"})
            state["devices"][token] = {"registeredAt": int(time.time())}
            save_state(state)
            return self._reply(200, {"ok": True})

        if path == "/activity-token":
            sid = req.get("sessionID", "")
            state.setdefault("activityTokens", {})[sid] = req.get("activityToken", "")
            save_state(state)
            return self._reply(200, {"ok": True})

        if path == "/notify":
            token = req.get("deviceToken", "")
            if not token:
                return self._reply(400, {"error": "missing deviceToken"})
            # Opaque alert: which session wants you, nothing else.
            payload = {
                "aps": {
                    "alert": {
                        "title": req.get("title", "A session needs you"),
                        "body": req.get("body", "Tap to jump back in."),
                    },
                    "sound": "default",
                },
            }
            if req.get("hostId"):
                payload["hostId"] = req["hostId"]
            send_apns(token, payload)
            return self._reply(200, {"ok": True})

        return self._reply(404, {"error": "not found"})


def main() -> int:
    port = int(os.environ.get("PORT", "8731"))
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"[relay] listening on :{port} (state at {STATE_PATH})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[relay] stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
