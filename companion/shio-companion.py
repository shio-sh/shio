#!/usr/bin/env python3
"""
Shio companion — reference implementation (Phase 2 scaffold).

Shows a pairing QR and runs a one-shot local handshake so the Shio app on your
phone can authorize itself on this machine, WhatsApp-Web style:

    1. This script prints connection info as a QR (and a shio:// link + JSON
       fallback you can paste into the app on a simulator).
    2. You scan it in Shio → Hosts → "Pair a machine".
    3. The app POSTs its SSH public key to this script's /pair endpoint.
    4. This script validates the one-time token and appends the key to
       ~/.ssh/authorized_keys. Shio can now connect.

This is the portable reference (Mac / Linux / Pi). Shio for Mac is its
polished wrapper; the Linux/Pi story is "run this script". Python 3 stdlib
only; `qrencode` is used for the QR if present, otherwise the link is printed.

RUNTIME NOTE: this is a scaffold. It implements the contract in
Shio/Core/Pairing/PairingPayload.swift and PairingService.swift, but the
end-to-end flow (reachability, host-key pinning, TLS for the endpoint) needs
validation on real devices + networks before it's production-trustworthy.
The pairing endpoint here is plain HTTP on the LAN/tailnet for the local case;
do not expose it to the public internet.
"""

import argparse
import getpass
import json
import secrets
import shutil
import socket
import subprocess
import sys
from base64 import urlsafe_b64encode
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

DEFAULT_PORT = 8730


def detect_host() -> str:
    """Best-effort reachable address: Tailscale IP if up, else LAN IP."""
    ts = shutil.which("tailscale")
    if ts:
        try:
            out = subprocess.run([ts, "ip", "-4"], capture_output=True, text=True, timeout=3)
            ip = out.stdout.strip().splitlines()[0].strip() if out.stdout.strip() else ""
            if ip:
                return ip
        except Exception:
            pass
    # Fallback: the address used to reach a public IP (no packets sent).
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return socket.gethostbyname(socket.gethostname())


def build_payload(args, token: str) -> dict:
    host = args.host or detect_host()
    return {
        "v": 1,
        "name": args.name or socket.gethostname(),
        "host": host,
        "port": args.ssh_port,
        "user": args.user or getpass.getuser(),
        "endpoint": f"http://{host}:{args.pair_port}/pair",
        "token": token,
    }


def show_qr(payload: dict) -> None:
    raw = json.dumps(payload, separators=(",", ":"))
    link = "shio://pair?d=" + urlsafe_b64encode(raw.encode()).decode().rstrip("=")
    qrencode = shutil.which("qrencode")
    print()
    if qrencode:
        # ANSI QR straight in the terminal — scan it with the phone.
        subprocess.run([qrencode, "-t", "ANSIUTF8", link])
    else:
        print("(install `qrencode` to render a scannable QR here)")
    print()
    print("Or paste this into Shio → Hosts → Pair → Paste:")
    print()
    print("  " + raw)
    print()
    print("Deep link:", link)
    print()


def authorize_key(pubkey: str) -> None:
    """Append an OpenSSH public key line to ~/.ssh/authorized_keys (idempotent)."""
    line = pubkey.strip()
    if not line.startswith("ssh-"):
        raise ValueError("not an OpenSSH public key line")
    ssh_dir = Path.home() / ".ssh"
    ssh_dir.mkdir(mode=0o700, exist_ok=True)
    ak = ssh_dir / "authorized_keys"
    existing = ak.read_text() if ak.exists() else ""
    if line in existing:
        return
    with ak.open("a") as f:
        if existing and not existing.endswith("\n"):
            f.write("\n")
        f.write(line + "\n")
    ak.chmod(0o600)


def serve(token: str, port: int) -> None:
    state = {"done": False}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):  # quiet
            pass

        def _json(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            if self.path.rstrip("/") != "/pair":
                self._json(404, {"error": "not found"})
                return
            length = int(self.headers.get("Content-Length", 0))
            try:
                req = json.loads(self.rfile.read(length) or b"{}")
            except Exception:
                self._json(400, {"error": "bad json"})
                return
            if not secrets.compare_digest(str(req.get("token", "")), token):
                self._json(403, {"error": "bad token"})
                return
            try:
                authorize_key(req.get("publicKey", ""))
            except Exception as e:
                self._json(400, {"error": str(e)})
                return
            self._json(200, {"ok": True})
            print("\n✓ Paired — added this device's key to authorized_keys.\n")
            state["done"] = True

    httpd = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Listening for the pairing handshake on :{port} … (Ctrl-C to stop)")
    try:
        while not state["done"]:
            httpd.handle_request()
    except KeyboardInterrupt:
        print("\nStopped.")


def main() -> int:
    p = argparse.ArgumentParser(description="Shio companion (pairing reference)")
    p.add_argument("--name", help="display name for this machine (default: hostname)")
    p.add_argument("--host", help="address the phone should SSH to (default: auto-detect)")
    p.add_argument("--user", help="SSH login user (default: current user)")
    p.add_argument("--ssh-port", type=int, default=22, help="SSH port (default: 22)")
    p.add_argument("--pair-port", type=int, default=DEFAULT_PORT, help=f"pairing server port (default: {DEFAULT_PORT})")
    args = p.parse_args()

    token = secrets.token_urlsafe(18)
    payload = build_payload(args, token)
    show_qr(payload)
    serve(token, args.pair_port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
