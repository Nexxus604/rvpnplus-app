# AmneziaWG integration into our sing-box build — research findings

**Date:** 2026-05-25
**Status:** Research only, no code changes yet. Captured for execution in Phase 1.

## Bottom line

Upstream sing-box (SagerNet/sing-box) **will not accept AWG**:
- PR [#2670](https://github.com/SagerNet/sing-box/pull/2670) by reflog (2025-03) — closed in 2 days
- Issue [#4045](https://github.com/SagerNet/sing-box/issues/4045) (AWG 2.0) — closed "not planned" (2026-04)
- Hiddify mainline also passive: [hiddify-app#1761](https://github.com/hiddify/hiddify-app/issues/1761) and [Hiddify-Manager#4736](https://github.com/hiddify/Hiddify-Manager/issues/4736) closed/stale

We must run our own fork. Two mature forks already exist; we don't need to patch sing-box from scratch.

## Recommended path: hoaxisr/amnezia-box

Repo: <https://github.com/hoaxisr/amnezia-box>

- Fork chain: `SagerNet/sing-box → amnezia-vpn/sing-box → hoaxisr/amnezia-box`
- Tracks upstream **stable-next** on `main`, dev-next on `alpha`
- Latest release: `v1.13.8-awg2.0`
- ~2,300 commits, actively rebased
- License: GPL-3.0 (compatible with our Hiddify-Next fork's GPL-3.0)
- `amneziawg-go v0.2.17` added as direct dependency alongside `sagernet/wireguard-go` — **no `replace` directive needed**
- AWG outbound type lives separately; regular WireGuard still works (we still need it for non-RU exits)
- `patches/amneziawg-go/apply.sh` applies post-`go mod download` patches (`0001-add-counter-obf-tag`, `0002-fix-s4-keepalive-padding`)

## Fallback: amnezia-vpn/amnezia-box

Repo: <https://github.com/amnezia-vpn/amnezia-box>

- Official Amnezia team's sing-box fork (last touched 2025-11-28)
- Less transparent than hoaxisr (their `go.mod` on dev-next doesn't yet list amneziawg-go)
- Slower release cadence

Use as bailout if hoaxisr ever goes dormant.

## Integration plan

Hiddify-Next has `libcore/` as a git submodule that wraps sing-box and exposes a gomobile `.aar`/`.framework` to Flutter. To swap in AWG support:

1. Fork `hoaxisr/amnezia-box` → `Nexxus604/sing-box-awg`. Pin to its latest `v1.13.x-awg2.0` tag.
2. In our `libcore/` submodule's `go.mod`, change `github.com/sagernet/sing-box` to our fork via `replace` directive.
3. Run `make libcore` on dev-runner (it has Go 1.22 — **may need to bump to 1.24.7** per hoaxisr's `go.mod`).
4. The patches in `patches/amneziawg-go/apply.sh` need to run between `go mod download` and `go build`.
5. Expose `amnezia-wg` outbound type in our JSON profile schema.
6. Add to Flutter outbound-form picker (we'll likely hide it behind "Stealth WireGuard" label per TZ §9.3).

## Effort estimate

- **2–5 working days** for first green Android build + manual AWG connect
- **1.5–3 weeks** to ship end-to-end:
  - iOS framework rebuild + NetworkExtension test
  - Windows tun integration
  - CI rebuilds
  - JSON schema validation
  - Hiddify profile-import support
  - Monitor probes
  - End-to-end test against our existing AWG node

## Landmines & known issues

### Server compatibility
**Our existing AWG nodes ship version 1.5** (Jc/Jmin/Jmax/S1-S4/H1-H4 fields — see [[reference_awg_chain_msk3]] for current ansible/marzban setup). hoaxisr's `awg2.0` tag supports both 1.5 and 2.0, but **client can't speak 2.0 to a 1.5 server** — handshake silently fails. Plan: use 1.5 mode client-side until we explicitly upgrade nodes.

### Go version
hoaxisr's `go.mod` pins `go 1.24.7`. Our dev-runner has 1.22.2. We need to upgrade Go on the runner before `make libcore` succeeds. Cross-check that gomobile + NDK r27 build against Go 1.24.

### iOS Network Extension memory cap
iOS NE has a 15 MB memory cap. AWG-go's obfuscation buffers add ~1–2 MB vs vanilla WG. AmneziaVPN's own iOS app ran into this — they ship a stripped build. Watch for OOM on older iPhones.

### `replace wireguard-go` is a red herring
Old forum threads suggest replacing `sagernet/wireguard-go` with `amneziawg-go` in the WireGuard outbound's `go.mod` — **don't do this**. It breaks regular WG outbound (still needed for non-RU exits). amneziawg-go and wireguard-go coexist as different module paths; use the AWG outbound type instead.

### Rebase debt
Every sing-box stable bump from Hiddify-Next (roughly monthly) means re-syncing the fork. hoaxisr does this for free today; budget ~0.5 day/month if they ever go dormant.

### Branch selection
Use hoaxisr's `main` (stable). `alpha` tracks sing-box dev-next and breaks regularly.

## License compatibility

| Component | License | OK with ours? |
|---|---|---|
| sing-box | GPL-3.0 | ✅ same |
| amneziawg-go | MIT | ✅ permissive, fine with GPL |
| AWG Linux kernel module | GPL-2.0 | ✅ not redistributed by us |
| Our Flutter client (R-VPN+) | GPL-3.0 (Hiddify) | — |

No conflicts.

## Recommended first execution step (hacky-but-working v1)

1. Fork `hoaxisr/amnezia-box` to `Nexxus604/sing-box-awg`, pin to latest `v1.13.x-awg2.0` tag
2. Bump Go on dev-runner to 1.24.7 (`go install golang.org/dl/go1.24.7@latest`)
3. In `rvpnplus-app`/libcore submodule's `go.mod`, add `replace github.com/sagernet/sing-box => github.com/Nexxus604/sing-box-awg <tag>`
4. Run `make libcore` on dev-runner
5. If build is green, ship to Phase-1 Android testers and try connecting to an existing AWG 1.5 node (e.g. ger1)
6. **Only after the round-trip works on a real phone**, touch Flutter JSON schema / profile-import / iOS framework

Goal for first working AWG handshake from R-VPN+ Flutter app on a test phone: **end of week 1 of Phase 1** if dev-runner cooperates.

## Reference links

- [hoaxisr/amnezia-box](https://github.com/hoaxisr/amnezia-box) — primary fork candidate
- [amnezia-vpn/amnezia-box](https://github.com/amnezia-vpn/amnezia-box) — fallback fork
- [amnezia-vpn/amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) — Go AWG impl (MIT, 1071 commits, active)
- [SagerNet/sing-box PR #2670 (closed)](https://github.com/SagerNet/sing-box/pull/2670) — reference implementation by reflog
- [SagerNet/sing-box issue #4045 (not planned)](https://github.com/SagerNet/sing-box/issues/4045) — upstream's "no" on AWG
- [Amnezia docs / AWG protocol](https://docs.amnezia.org/documentation/amnezia-wg/) — 1.5 vs 2.0 field reference for our schema
