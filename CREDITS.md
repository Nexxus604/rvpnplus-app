# Credits & Acknowledgements

R-VPN+ is built on the foundation of excellent open-source projects. We owe deep
thanks to the maintainers and contributors of all the upstream software listed
below.

## Hiddify-Next

R-VPN+ is a **fork of [Hiddify-Next](https://github.com/hiddify/hiddify-next)** —
a cross-platform multi-protocol proxy frontend. The original UI scaffolding,
Flutter project structure, sing-box integration, and many platform-specific
build configurations come from Hiddify-Next.

Hiddify-Next is licensed under **GPL-3.0**. R-VPN+ is therefore also distributed
under GPL-3.0 (see `LICENSE`).

We track the upstream Hiddify-Next repository as a git remote (`upstream`) and
periodically merge improvements. Modifications, additions, and customisations
made for R-VPN+ are committed on top of the upstream history in this repository.

The baseline fork point is tagged `baseline-hiddify-fork` in this repository
(corresponds to upstream commit `fbc6cbd4`).

## sing-box

The underlying VPN/proxy engine is **[sing-box](https://github.com/SagerNet/sing-box)**
(licensed GPL-3.0), the universal proxy platform that powers all connection logic.

## amneziawg-go

For our AmneziaWG protocol support, we use
**[amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go)** (licensed MIT),
the Go implementation of the AmneziaWG protocol — a hardened WireGuard variant
with anti-DPI features.

## Flutter

The cross-platform UI framework. © Google. BSD-style licensed.

## Other dependencies

For the full list of Flutter packages and their licenses, see the in-app
"About → Open Source Licenses" screen, which lists every transitive dependency.

---

If you spot a missing attribution, please open an issue or pull request —
we want to give credit where it's due.
