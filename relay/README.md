# Shio away-push relay

The one consciously-scoped Shio-operated piece: a thin, **opaque** relay that
forwards "a session needs you" triggers from your machine to your phone via
APNs. It knows *which session* wants you and nothing else — never your code,
never terminal output. It's **self-hostable**, so you can run your own and
point Shio at it instead of any Shio-run instance.

`shio-relay.py` is the reference implementation (Python). Pair it with
`companion/shio-away-watcher.py`, which does the detection and calls `/notify`.

## Wire it up

1. Run the relay somewhere both your machine and APNs can reach, behind TLS:
   ```sh
   PORT=8731 python3 shio-relay.py
   ```
2. Point Shio at it: set the App Group default `shio.relay.baseURL` to your
   relay's base URL. The app registers its APNs device token on launch
   (`PushService`).
3. Run the away-watcher on the machine for the session you care about:
   ```sh
   python3 ../companion/shio-away-watcher.py --session shio-myproject \
       --relay https://your-relay.example --device <device-token> --host-id <id>
   ```

## Endpoints

| Method/Path        | Body                                              | Purpose |
|--------------------|---------------------------------------------------|---------|
| `POST /register`       | `{ deviceToken }`                              | phone registers for push |
| `POST /activity-token` | `{ deviceToken, activityToken, sessionID }`    | Live Activity remote-update token |
| `POST /notify`         | `{ deviceToken, hostId?, title?, body? }`      | companion: an agent needs you |

## APNs (the infra piece)

APNs needs HTTP/2 + token (JWT ES256) auth with your `.p8` key. The relay sends
real pushes when `httpx` + `pyjwt[crypto]` are installed and these env vars are
set, else it dry-run logs:

```
APNS_KEY_PATH  AuthKey_XXXX.p8
APNS_KEY_ID    10-char key id
APNS_TEAM_ID   10-char team id
APNS_TOPIC     sh.shio.app
APNS_ENV       sandbox | production
```

## Status / TODO (flagged)

- [ ] **E2E encryption of the trigger** — the payload is already content-free, but the "which session" id should be opaque/rotating so the relay operator learns nothing. Not yet implemented.
- [ ] **Auth** between companion and relay (per-device shared secret) so only your machines can post `/notify`.
- [ ] **Live Activity remote updates** — `/activity-token` is captured; pushing `content-state` updates to the LA via APNs is not wired yet.
- [ ] Real-device + deployed-relay validation of the whole path (`PushService` → relay → APNs → phone).
- [ ] Replace JSON-file state with something durable if you run this for more than yourself.
