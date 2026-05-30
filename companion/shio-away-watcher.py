#!/usr/bin/env python3
"""
Shio away-watcher — reference implementation (Phase 6 scaffold).

Runs on your machine and watches a tmux session for an agent that blocks on
you (an approval/input prompt) or finishes, then pings the Shio relay so your
phone gets a "session needs you" push — even with the app closed.

This is the server-side twin of the app's output-watching detection
(Shio/Core/Agents/AgentDetection.swift); the waiting heuristics are kept
deliberately in sync. It reads the session non-invasively via
`tmux capture-pane`, so it doesn't disturb what you (or the agent) are doing.

Usage:
  python3 shio-away-watcher.py \
      --session shio-myproject \
      --relay https://your-relay.example \
      --device <apns-device-token> \
      [--host-id <shio-host-id>] [--interval 4]

RUNTIME/INFRA NOTE: scaffold. Needs tmux locally, a reachable relay
(relay/shio-relay.py), and the relay wired to APNs. The device token comes
from the phone (PushService logs/registers it); host-id lets the push deep-link
straight to the right machine. Detection is heuristic — tune before relying on
it for anything load-bearing.
"""

import argparse
import re
import subprocess
import sys
import time
import urllib.request

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

WAITING_MARKERS = [
    "do you want to proceed", "do you want to make this edit",
    "allow this command", "allow command", "run this command",
    "proceed?", "continue?", "overwrite?", "are you sure",
    "(y/n)", "[y/n]", "(yes/no)", "press enter to continue",
    "❯ 1. yes", "1. yes",
]
RUNNING_MARKERS = ["esc to interrupt", "thinking", "working", "generating"]


def classify(tail: str) -> str:
    """Mirror of AgentDetector.classify: none/running/waiting/finished."""
    clean = ANSI_RE.sub("", tail).lower()
    window = clean[-800:]
    if any(m in window for m in WAITING_MARKERS):
        return "waiting"
    if any(m in clean[-400:] for m in RUNNING_MARKERS):
        return "running"
    # Returned to a shell prompt at the very end → finished.
    stripped = clean.rstrip()
    if stripped and stripped[-1] in "$%#➜❯":
        return "finished"
    return "none"


def capture(session: str) -> str:
    try:
        out = subprocess.run(
            ["tmux", "capture-pane", "-p", "-t", session],
            capture_output=True, text=True, timeout=5,
        )
        return out.stdout
    except Exception:
        return ""


def notify(relay: str, device: str, host_id: str | None, state: str) -> None:
    title = "A session needs you" if state == "waiting" else "Agent finished"
    body = "An agent is waiting on you." if state == "waiting" else "Your agent finished its turn."
    payload = {"deviceToken": device, "title": title, "body": body}
    if host_id:
        payload["hostId"] = host_id
    data = __import__("json").dumps(payload).encode()
    req = urllib.request.Request(
        relay.rstrip("/") + "/notify", data=data,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        print(f"[away-watcher] pushed: {state}")
    except Exception as e:
        print("[away-watcher] push failed:", e)


def main() -> int:
    p = argparse.ArgumentParser(description="Shio away-watcher (agent → push)")
    p.add_argument("--session", required=True, help="tmux session name (e.g. shio-myproject)")
    p.add_argument("--relay", required=True, help="relay base URL")
    p.add_argument("--device", required=True, help="phone APNs device token")
    p.add_argument("--host-id", help="Shio host id to deep-link the push to")
    p.add_argument("--interval", type=float, default=4.0, help="poll seconds (default 4)")
    args = p.parse_args()

    print(f"[away-watcher] watching tmux '{args.session}' every {args.interval}s")
    last = "none"
    try:
        while True:
            state = classify(capture(args.session))
            # Only push on a transition *into* an actionable state.
            if state != last and state in ("waiting", "finished"):
                notify(args.relay, args.device, args.host_id, state)
            last = state
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n[away-watcher] stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
