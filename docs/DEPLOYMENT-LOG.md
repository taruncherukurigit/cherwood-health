# Deployment Log — Site Launch (tarunc.com + cherwood.tarunc.com)

**Status:** Both sites live. `tarunc.com` / `www.tarunc.com` serving the personal portfolio; `cherwood.tarunc.com` serving the upgraded Cherwood Corporation project site. Both hosted on the existing `cherwood-dmz` container, riding the existing Cloudflare Tunnel — zero new open inbound ports.

## What was deployed

| Component | Detail |
|---|---|
| Portfolio site | `/var/www/portfolio/index.html`, nginx on port 8081 |
| Cherwood Corporation site | `/var/www/html/index.html`, nginx on port 80 (upgrade of the prior placeholder page) |
| Tunnel ingress | New `hostname` entries added to `/etc/cloudflared/config.yml` for `tarunc.com`, `www.tarunc.com`, alongside the existing `cherwood.tarunc.com` entry |
| DNS records | New CNAME records created via `cloudflared tunnel route dns`, routing both new hostnames through the existing tunnel |

## Real troubleshooting chain (interview-ready narrative)

1. **File transfer via console paste was deliberately avoided** for a 34KB HTML file, given the real console-paste corruption issues hit earlier in this project with content far smaller (a single SSH key). Used `pct push` from the Proxmox host instead — copies a file directly into a container's filesystem via the hypervisor, bypassing both the network path and any terminal paste-length limitations entirely. Good general lesson: know when a tool built for short interactive commands (a console) is the wrong tool for a bulk-file-transfer job, and reach for the one actually designed for it.

2. **A typo (`index.html~` instead of `index.html`) in a `pct push` destination path caused the new site to silently fail to appear** — the file transferred successfully, just to the wrong filename, so nginx kept serving the old cached-looking content with zero error message anywhere. Caught by explicitly `grep`-ing the live file for content unique to the new page, rather than trusting a visual "it looks the same as before" browser check — a repeat of the same discipline used throughout this project: verify the actual file content, don't assume a copy operation landed where intended.

3. **The Cloudflare Tunnel service failed to start after the config update**, with a specific, distinctive error: `SSL certificate problem: self-signed certificate` when the tunnel tried to reach Cloudflare's API — not a generic connectivity failure, but a very particular signature. Investigated methodically rather than guessed:
   - Ruled out a bad system clock (`date` confirmed correct)
   - Ruled out a broken CA certificate bundle (reinstalled `ca-certificates`, no change)
   - **Escalated to genuine concern** when the same suspicious IP (`208.91.112.55`) showed up for `api.cloudflare.com` regardless of which DNS resolver was asked — including Google's public `8.8.8.8`, an independent, external service. A single unexplained IP showing up consistently across multiple unrelated domains and multiple independent resolvers is a legitimate reason to suspect DNS-level interference, and it was treated as exactly that serious a possibility rather than dismissed.
   - **Scoped the problem before assuming the worst.** Rather than conclude the whole network was compromised, checked the FortiGate itself — a completely independent device on a completely independent VLAN — which resolved `api.cloudflare.com` correctly to a legitimate Cloudflare IP. This single test cleanly separated "isolated to one container" from "network-wide" or "ISP-wide," and ruled out any compromise scenario in about thirty seconds.
   - **Root cause, confirmed directly:** the same IP that kept appearing for unrelated lookups turned out to be the FortiGate's own DNS-filter block-page IP. `Guest_DMZ_Filter` (the DNS filter profile covering DMZ traffic, originally built in Part 10.6) was incorrectly categorizing and blocking `api.cloudflare.com` under a content category — the same underlying mechanism, and nearly the same failure signature, as the DuckDNS block from Part 11's SSL-VPN work. Confirmed with a direct `curl` request forcing the `Host` header to `api.cloudflare.com` while connecting straight to the suspicious IP, which returned FortiGuard's literal "Web Page Blocked!" HTML page — unambiguous proof.
   - This same root cause also explained an *earlier*, seemingly unrelated symptom from the same session: `apt install` commands failing with `403 Forbidden` against Debian's package mirrors, which had been shrugged off in the moment as an external mirror outage. In hindsight, it was the same DNS filter blocking `deb.debian.org` too — a good reminder that "unrelated-looking" failures happening close together in time are worth revisiting once a root cause for one of them is found, rather than assuming each was independently caused.

4. **Fixed by adding explicit wildcard allow entries** (`*.cloudflare.com`, `*.argotunnel.com`, `*.debian.org`) to the `Guest_DMZ_Filter` DNS filter profile — the same fix pattern established for DuckDNS in Part 11, now recognized and applied faster the second time.

5. **A leftover stale DNS `A` record for the bare root domain** (`tarunc.com`, pointing at an old registrar-parking IP unrelated to this project) blocked the tunnel's CNAME route from being created for that specific hostname, while the `www.tarunc.com` route succeeded cleanly in the same command. Diagnosed directly from Cloudflare's own specific, well-written error message (`"An A, AAAA, or CNAME record with that host already exists"`) rather than needing further investigation — a good example of an error message that told the entire story on its own. Fixed by deleting the two stale `A` records via the Cloudflare dashboard, then re-running the same route command successfully.

**Takeaway for the writeup:** the standout moment in this chain is the discipline shown when the DNS anomaly first surfaced — a serious possibility (network compromise) was taken seriously enough to investigate properly, but the investigation itself was methodical and scoped rather than panicked: check an independent device, get a clean yes/no on blast radius, then keep narrowing from there. The eventual root cause (an overly broad DNS filter category) was mundane, but treating the *possibility* of something worse with appropriate seriousness — while not jumping to conclusions before checking — is exactly the right instinct for a security-conscious engineer, and it's a good, honest story to be able to tell in an interview: "I saw a signal that looked concerning, I verified scope before reacting, and the actual cause turned out to be something I'd already fixed once before in this exact project — which meant I recognized and resolved it faster the second time."

## Sites now live

| URL | Content |
|---|---|
| `https://tarunc.com` / `https://www.tarunc.com` | Personal portfolio — resume, skills, Cherwood Health project summary |
| `https://cherwood.tarunc.com` | Cherwood Corporation — full project site with animated topology, build log, troubleshooting highlights |

## Flagged for future work (not blockers)

- `health.cherwood.tarunc.com` — a Tunnel DNS record discovered to already exist from earlier in the project, currently unused. Worth deciding what (if anything) to do with it, or removing it for tidiness.
- The `www.tarunc.com` and `tarunc.com` CNAME records both proxy through Cloudflare ("Proxied" status confirmed in the DNS dashboard) — standard and expected for a tunnel-routed hostname, worth understanding as distinct from a plain "DNS only" record for anyone reviewing the DNS configuration later.

---

*Standalone log — fold into the canonical `cherwood-health-guide.md` and `TROUBLESHOOTING-LOG.md` next time the master files are available in-session.*
