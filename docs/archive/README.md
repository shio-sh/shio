# Archive

Historical documents. Kept because they record how decisions were made, not because they describe Shio.

Every one of these predates the v1 scope cut, when Shio stopped being an agent-supervision product and became a terminal. Read them as snapshots, not as documentation. [`../../ROADMAP.md`](../../ROADMAP.md) is the current picture.

| File | What it was | Why it's here |
|---|---|---|
| `SHIO_STATE_OF_THE_UNION.md` | Architecture and product overview, mid-2026 | Describes the "cross-machine command center for agents" that was cut. The subsystems it details as central, away-push and lock-screen approve and deny, no longer exist. |
| `SHIO-PRE-BETA-REVIEW.md` | Multi-agent review, June 2026 | A pre-beta audit that itemized security issues by file and line. **Everything it raised was fixed before 1.0 shipped**, including the host-key and pairing findings it leads with. It is kept for the reasoning, not as a live issue list. |
| `SHIO-POLISH-AUDIT.md` | 123-finding code audit, 12 June 2026 | Tier 0 and Tier 1 were burned down the same day across roughly 30 commits, and re-verified on 3 July. The remaining items were folded into the roadmap or overtaken by the scope cut. |
| `landing-page-brief.md` | Brief for shio.sh, pre-launch | Written when Shio was "a premium iOS and iPadOS SSH client", before the Mac app existed. The site it describes has since been built and rewritten. |
| `landing-setup-page-brief.md` | Brief for shio.sh/setup | Same vintage. The page exists; this is the thinking behind it. |
| `macos-companion.md` | Proposed Mac architecture | Describes a UPnP and STUN signalling service for device pairing. It was never built. Shio reaches machines over plain SSH, on your network or your own Tailscale, with no relay of ours anywhere. |
| `handover/` | Session handover notes | Point-in-time state dumps. Useful as history, wrong as documentation. |

If you are looking for a current security contact, see [`../../SECURITY.md`](../../SECURITY.md).
