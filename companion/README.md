# Shio companion

The companion is the thing you run on a machine you own (Mac, Linux box, Raspberry Pi)
to pair it with Shio on your phone — WhatsApp-Web style. Scan once; Shio is trusted
on that machine until the key is rotated.

`shio-companion.py` is the **portable reference implementation** (Python 3 stdlib).
Shio for Mac will ship as its polished wrapper around this same handshake; the
Linux/Pi story is "run this script".

## Use

```sh
python3 shio-companion.py
```

It prints a QR (needs `qrencode` for a scannable one; otherwise it prints a
`shio://pair?d=…` link and a JSON blob you can paste into Shio on the simulator).
In Shio: **Hosts → Pair a machine** → scan. The app sends its SSH public key to the
companion's local `/pair` endpoint; the companion appends it to
`~/.ssh/authorized_keys`. Done.

Flags: `--name`, `--host`, `--user`, `--ssh-port`, `--pair-port`.

## The contract

The QR encodes a `PairingPayload` (see `Shio/Core/Pairing/PairingPayload.swift`):

```json
{ "v": 1, "name": "…", "host": "100.x.y.z", "port": 22, "user": "you",
  "endpoint": "http://100.x.y.z:8730/pair", "token": "<one-time>" }
```

The phone POSTs `{ "publicKey": "ssh-ed25519 …", "token": "…" }` to `endpoint`.

## Status / TODO (Phase 2 → Phase 6)

This is a **scaffold**. Before it's production-trustworthy:

- [ ] Host-key pinning: carry the host key fingerprint in the payload and verify TOFU on the phone (`PairingPayload.fingerprint` is wired but unused).
- [ ] Transport hardening: the `/pair` endpoint is plain HTTP for the local/tailnet case. Add TLS (or scope strictly to the tailnet) before any non-local use; never expose it to the public internet.
- [ ] Real-device validation of reachability + the URLSession handshake in `PairingService.swift`.
- [ ] Repo discovery: enumerate git repos on the machine and let the app pick them as Projects (Phase 2 remainder).
- [x] Phase 6: `shio-away-watcher.py` is the always-on away-watcher — server-side agent detection that pings the relay (`relay/`) so your phone gets a "session needs you" push with the app closed. Still needs a deployed relay + APNs key; see `relay/README.md`.
