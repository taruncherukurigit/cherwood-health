# Troubleshooting Log — Cherwood Health

Every real bug hit during this build, in chronological/part order, with root cause and fix. Nothing here is hypothetical — this is what actually happened, documented honestly rather than cleaned up to look like everything worked on the first try. Read this if you want to understand not just *what* was built, but *how it was actually debugged*.

---

## Part 3 — Locked out of the FortiGate admin GUI

**Symptom:** after changing the default hardware switch's IP from `192.168.1.99/24` to `10.99.99.1/24` (to resolve a subnet conflict with the Verizon router's own DHCP range), the admin GUI became completely unreachable.

**Root cause:** the laptop's own network adapter was still configured for the old `192.168.1.x` range and had no way to reach the newly-changed `10.99.99.1` subnet.

**Fix, and why it matters:** rather than shuffle cables to find a still-working path back in (a real option, since some interfaces hadn't changed), the console port was used instead — the standard, correct way network engineers recover from a self-inflicted GUI lockout. Connected via the FortiGate's physical console port at 9600 baud, logged in via CLI, and fixed the actual setting directly:
```
config system interface
edit "VLAN10_Trusted"
set allowaccess https ping ssh
end
```
**Lesson:** always know your device's console access path before you need it under pressure — it's the reliable fallback when network-based management access breaks, which it eventually will.

---

## Part 6 — Guest SSID couldn't get `guest-mode`

**Symptom:** attempting to add the `guest-mode` designation to the `Cherwood-Guest` SSID failed with:
```
Dot11Radio1: Guest-ssid already existing on ssid Cherwood-Staff
```

**Root cause:** Cisco Autonomous APs allow only **one** SSID per radio to hold the `guest-mode` flag. Both SSIDs were initially configured on the same radio, and `Cherwood-Staff` had claimed that slot first.

**Fix:** split the two SSIDs across the AP's two separate radios (2.4GHz and 5GHz) — `Cherwood-Staff` on Radio0, `Cherwood-Guest` alone on Radio1 — giving each radio its own independent `guest-mode` slot.

**Lesson:** this wasn't a missed step or typo — it was a hard vendor limit, discovered by reading the actual rejection message rather than assuming user error. Real hardware has real constraints simulators often don't enforce.

---

## Part 9-10 — VLAN 40 not actually usable despite being in the trunk's allowed list

**Symptom:** VLAN 40 (DMZ) traffic wasn't passing correctly even though it had been added to the trunk's allowed-VLAN list on the switch.

**Root cause:** adding a VLAN to a trunk's *allowed list* is not the same as the VLAN actually existing in the switch's VLAN database. It needed to be formally created (`vlan 40` / `name DMZ`) as its own object, separate from just permitting it across an existing trunk.

**Lesson:** on Cisco switches, a VLAN needs to exist as a database entry before trunk membership does anything meaningful with it — a subtle but important two-step process.

---

## Part 10 — Kindle digest pipeline broke after VLAN migration

**Symptom:** after moving the Proxmox host and its containers onto the newly-segmented Servers VLAN, the Kindle/RSS digest automation stopped working — no clear error, just silent failure partway through the pipeline.

**Root cause, found via `journalctl` on the receiver container rather than guessing:** the new Servers VLAN had no outbound-to-internet firewall policy at all. The containers could reach each other locally, but had zero path to the actual internet — breaking DNS resolution, the RSS fetch step, and outbound SMTP for delivery, all at once, all from the same underlying cause.

**Fix:** created `Servers_to_Internet` (VLAN30 → wan1, ACCEPT, NAT). Confirmed via `ping 8.8.8.8` from inside the container (worked, low-latency, resolving the root cause directly) before re-running the full pipeline end-to-end.

**Lesson:** a missing outbound internet policy for an entire new VLAN can look like several unrelated failures (DNS, RSS fetch, email delivery) simultaneously — always check the most fundamental layer (does this VLAN have internet access at all?) before chasing what look like separate application-level bugs.

---

## Part 10.5 — Cloudflare Tunnel kept dying after "successful" test runs

**Symptom:** the DMZ site would work during a manual foreground test (`cloudflared tunnel run ...`), then go dark shortly after — repeatedly.

**Root cause, confirmed via `ps aux | grep cloudflared` and the tunnel's own logs:** running the tunnel as a plain foreground process meant it terminated the moment the terminal session sending the command was interrupted (a `Ctrl+C`, a disconnect, closing the console) — the log literally showed `Initiating graceful shutdown due to signal interrupt`.

**Fix:** wrapped it in a proper systemd service via `cloudflared service install`, then `systemctl start` / `enable`. This survives terminal disconnects, container reboots, and crashes (systemd restarts it automatically).

**Lesson:** "it worked when I tested it" and "it's actually running as a persistent service" are two different claims — verify a service survives disconnection before considering deployment done, not just that a manual test succeeded once.

---

## Part 10.6 — Confirming DNS filtering without a false positive

**Challenge:** early attempts to test DNS filtering (visiting a known test-malware URL from a Guest device) were ambiguous — Guest also has a captive portal in its traffic path, so a block could have come from either mechanism, or even the browser's own built-in Safe Browsing feature, muddying the test.

**Fix:** tested from the **DMZ** container instead (`curl http://testsafebrowsing.appspot.com/s/malware.html`), which has DNS filtering but no captive portal at all — isolating the variable. The response came back as FortiGate's own literal block page (`Fortinet Secure DNS Service Portal — Web Page Blocked!`), unambiguous proof the FortiGate's own filter was the actual mechanism intercepting the request.

**Lesson:** when multiple mechanisms could plausibly explain the same observed result, design a test that isolates just the one thing you're actually trying to confirm — don't accept the first plausible-looking result at face value.

---

## Part 11 — SSL-VPN, a five-part chain

This part had the most stacked, sequential bugs of the whole project — worth reading in full as a single narrative, since each one masked the next until resolved.

**1. Cipher self-conflict.** `show vpn ssl settings` (abbreviated view) looked fine; `show full-configuration vpn ssl settings` revealed `banned-cipher SHA1 SHA256 SHA384` directly conflicting with a TLS-1.3-only `ciphersuite` list that *requires* SHA256/SHA384 — leaving zero valid ciphers to negotiate. Fixed with `unselect banned-cipher SHA256` / `SHA384`, correctly leaving SHA1 banned.

**2. Port forward silently not saved.** The Verizon router's port-forward rule appeared in the UI table but hadn't actually committed — confirmed via an external port-checker tool reporting the port closed. Fixed by re-adding and explicitly verifying with a hard browser refresh.

**3. Missing firewall policy.** SSL-VPN being enabled and the port being open doesn't mean traffic is *permitted* — FortiGate needs an explicit policy from `wan1` to the SSL-VPN tunnel interface, scoped to the actual VPN user. Created `SSLVPN_to_Trusted`.

**4. The dominant root cause: Tailscale.** Running concurrently on the test phone, competing with FortiClient's own VPN interface for routing priority — the actual reason most connection attempts were failing with a generic, uninformative "SSL exit error" before authentication was ever reached. Disabling it was the step that finally produced real progress.

**5. Final password confirmation.** After all of the above, a stale/mistyped password briefly produced "Authentication failure" — resolved by resetting to a fresh, carefully-typed password.

**Lesson, stated once for the whole chain:** a single generic error message (in this case, "SSL exit error," repeated identically across multiple distinct root causes) can mask several independent problems. Fixing one real bug and still seeing the same symptom doesn't mean the fix was wrong — it can mean there's a second, unrelated bug still hiding behind it.

---

## Part 12/13 — Branch Office, six real issues in sequence

**1. Interface administratively down by default.** Cisco *router* interfaces (unlike switch ports) ship shut down. `no shutdown` on `GigabitEthernet0/0` was required before the link would come up at all.

**2. PING blocked at the interface level.** Even after the link showed up/up, pings failed 100%. Root cause: the FortiGate's `internal2` interface had PING unchecked under Administrative Access — a permission gate entirely separate from firewall policy.

**3. RIP converged correctly but the internet still didn't work.** Both routers correctly learned each other's specific advertised networks (confirmed via `show ip route rip` and `get router info routing-table rip`), but Branch still couldn't reach `8.8.8.8`. Root cause: RIP only knows what's explicitly listed in its config — nothing tells it "send anything else toward HQ." Fixed with a static default route: `ip route 0.0.0.0 0.0.0.0 10.10.99.1`.

**4. No firewall policy for Branch traffic at all.** Same lesson as Part 11: a route existing doesn't mean the firewall permits it. Created `Branch_to_Internet` (ACCEPT+NAT) and `Branch_to_HQ_DENY` (explicit, logged DENY) — the latter deliberately mirroring the Guest isolation pattern.

**5. Planned AP hardware turned out to be unusable.** Full detail in [`ARCHITECTURE.md`](ARCHITECTURE.md#hardware-substitution--branch-access-point) — Lightweight firmware, unrecoverable secondhand credentials, documented honestly and substituted with a TP-Link.

**6. Branch client got a private IP with no internet.** The TP-Link's WAN port never received a real `10.20.0.x` address. Root cause: no DHCP pool existed on the 1921 for its Branch-facing interface. Fixed with `ip dhcp pool BRANCH-WAN`, confirmed via `show ip dhcp binding`.

---

## Part 14 — Monitoring, repeated permission gaps and a config-paste bug

**1. SNMP timed out despite correct community-string config.** Same root pattern as the Part 12/13 PING issue: `VLAN10_Trusted` had SNMP unchecked under Administrative Access. Also required a *new* firewall policy (`Servers_to_Trusted_Monitoring`, VLAN30→VLAN10) since only the reverse direction had ever existed.

**2. Same pattern repeated for the Branch router.** Querying the 1921 via SNMP from the monitoring container also timed out — this time because no policy existed for `VLAN30_Servers → internal2` at all. Created `Servers_to_Branch_Monitoring`.

**3. A `cat << 'EOF'` heredoc was accidentally pasted into an open `nano` session** instead of a live shell prompt, writing the literal shell commands into `prometheus.yml` as plain-text file content rather than executing them — producing invalid YAML that Prometheus tolerated enough to keep running on its prior good config, silently masking that a new scrape job had never actually been added. Caught by explicitly `cat`-ing the file to inspect its real contents rather than assuming the paste landed correctly.

**4. Grafana's host CPU/memory panels showed implausible values** (memory readings over 100%). Verified against ground truth with `top` run directly on the container, confirming the dashboard numbers — not the underlying system — were wrong. Root cause: unprivileged LXC containers can reflect the Proxmox *host's* `/proc/meminfo`, not the container's own assigned limits — a known category of limitation when monitoring containerized workloads with tools designed primarily for VMs/bare metal. Fixed practically with `clamp_max(..., 100)` and documented as an acknowledged limitation directly on the dashboard, rather than presented as fully accurate.

---

## Part 15/16 — Automation, the richest chain in the project (nine distinct issues)

**1. Ed25519 key rejected.** The 1921's IOS SSH implementation only supports RSA keys for pubkey-chain auth. Generated a separate RSA 2048-bit key specifically for Cisco compatibility.

**2. Console paste corruption.** Pasting the long base64 key as one unbroken line repeatedly failed (`%SSH: Failed to decode the Key Value`). Fixed by chunking the key into ~64-character lines and stripping the `ssh-rsa` prefix/comment — the format Cisco's `key-string` mode actually expects.

**3–5. Three layered SSH client/server compatibility errors**, each only visible after fixing the previous one: `No matching cipher found` → `No matching key exchange method found` → `No matching host key type found`. Fixed by adding, one at a time, `-c aes256-cbc`, `-oKexAlgorithms=+diffie-hellman-group14-sha1`, and `-oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedKeyTypes=+ssh-rsa`.

**6. A fully-working SSH setup vanished after a router reload**, because it had only ever been configured in the running-config and never saved with `write memory`. A genuinely costly, memorable lesson about the difference between running-config and startup-config.

**7. Stale host-key cache after regenerating the router's SSH host key** — SSH correctly refused to connect, warning of a possible man-in-the-middle attack, since the cached identity in `known_hosts` no longer matched. Fixed narrowly (`ssh-keygen -R`, clearing just the one stale entry) rather than disabling host-key verification globally.

**8. FortiGate backup silently truncated at 217 lines**, cutting off mid-statement with no error reported by the script. Root cause: FortiGate's own `--More--` output pager blocks non-interactive SSH sessions, which have no way to send the keypress it's waiting for. Fixed by disabling the pager first (`config system console / set output standard / end`) in the same SSH session, before the actual config pull.

**9. Isolation-check script had a real logic bug of its own**, discovered only because it was deliberately tested against a real, intentionally-disabled policy rather than trusted on the strength of a single "looks fine" run. The script searched *forward* from a policy's `set name` line for its action/status, but FortiGate writes `set status disable` *before* `set name` in its config output — meaning a disabled policy was structurally invisible to the check as originally written. Fixed by properly parsing whole policy blocks (using FortiGate's own `next` terminator as an awk record separator) instead of assuming a fixed field order.

**Lesson for this whole part:** a check that has never been proven to actually catch a failure is not a trustworthy check — several of these bugs were only found because the fix was validated against a deliberately broken real scenario, not just re-run against the known-good case and assumed correct.

---

## Part 17 — "No log entry" doesn't mean "nothing happened"

**Symptom:** a real port-scan and ping-reachability test from the DMZ against the Trusted VLAN was clearly being blocked (100% packet loss, all ports closed/filtered) — but produced **zero** entries in Forward Traffic, Local Traffic, or Security Events, despite violation logging being confirmed enabled.

**Investigation, ruled out in order:** a routing gap (checked, not the cause — the network was properly directly-connected), the same interface-level PING permission issue seen twice before in this project (checked directly via screenshot, PING was actually enabled this time), and a GUI search-filter that appeared not to work as expected (noted, not chased further once a better tool was available).

**Resolution:** used `diagnose sniffer packet` — a live packet capture directly on the FortiGate CLI, independent of whatever the logging subsystem chooses to record — to observe ground truth. This showed ICMP requests genuinely **arriving** at the firewall, with **no reply ever sent** — proof the FortiGate was actively receiving and denying the traffic, just in a category (denial of traffic addressed *to* the firewall's own interface, as opposed to traffic *forwarded through* it) that FortiOS's standard GUI log views don't surface, even with logging enabled.

**Lesson:** an absence of expected log entries is not proof that nothing happened — it can just as easily mean you're looking in the wrong log category. When the stakes of "did this actually get blocked" matter, use a lower-level, ground-truth diagnostic (a packet capture) rather than concluding from silence in one specific view.

---

## Deployment — The "are we hacked?" DNS filter chain

**Symptom:** while deploying the personal portfolio site (`tarunc.com`) alongside an upgrade to the Cherwood Corporation project site, the Cloudflare Tunnel service began failing to start, with a distinctive error: `SSL certificate problem: self-signed certificate` when attempting to reach Cloudflare's own API.

**Investigation, methodical rather than panicked:**
- Ruled out a bad system clock (checked, correct)
- Ruled out a stale/broken CA certificate bundle (reinstalled `ca-certificates`, no change)
- **A genuinely concerning signal emerged:** the exact same suspicious IP address kept appearing as the resolved address for `api.cloudflare.com`, regardless of which DNS server was asked — including Google's independent public resolver (`8.8.8.8`). A single unexplained IP showing up consistently across multiple unrelated domains and multiple independent, external resolvers is a legitimate reason to suspect DNS-level interference, and — when asked directly whether this meant a compromise — the honest answer was: possibly, and it deserved a real check before being dismissed.
- **Scoped the blast radius before assuming the worst.** Rather than treating this as network-wide, a completely independent device on a completely independent VLAN (the FortiGate itself) was used as a control test — it resolved `api.cloudflare.com` correctly, to a legitimate Cloudflare IP, immediately ruling out "the whole network is compromised" or an ISP-level issue, and narrowing the problem to just the one container.
- **Root cause, confirmed directly:** the suspicious IP turned out to be the FortiGate's own DNS-filter block-page. `Guest_DMZ_Filter` (built back in Part 10.6) was incorrectly categorizing and blocking `api.cloudflare.com` — nearly the identical failure signature and mechanism as the DuckDNS block from Part 11. Confirmed beyond doubt with a `curl` request forcing the `Host` header to `api.cloudflare.com` while connecting directly to the suspicious IP, which returned FortiGuard's literal "Web Page Blocked!" page.
- **This also explained an earlier, seemingly unrelated symptom from the same session** — `apt install` commands failing with `403 Forbidden` against Debian's package mirrors, initially shrugged off as an external mirror outage. Same DNS filter, same root cause, different domain caught in the same overly broad category.

**Fix:** added explicit wildcard allow entries (`*.cloudflare.com`, `*.argotunnel.com`, `*.debian.org`) to the `Guest_DMZ_Filter` profile — the same fix pattern established for DuckDNS in Part 11, recognized and applied faster this time.

**Lesson:** when a signal looks like it could indicate something serious (in this case, potential DNS hijacking or compromise), the right response is neither to panic nor to dismiss it — it's to run a fast, independent, well-scoped test that gives a clean answer about blast radius before doing anything else. Checking an unrelated device on an unrelated VLAN took thirty seconds and immediately turned "is my whole network compromised?" into "something specific to one container is misbehaving" — a completely different, much less urgent problem. The eventual cause was mundane (an over-broad content filter), but the instinct to verify scope before reacting is exactly the right one regardless of what the cause turns out to be.

---

## Cross-cutting patterns across the whole project

A few lessons showed up more than once, in different parts, worth stating as general principles rather than one-off fixes:

1. **A route existing does not mean traffic is permitted.** Seen independently in SSL-VPN (Part 11), Branch routing (Part 12/13), and SNMP monitoring (Part 14). Routing and firewall policy are two separate layers; both need to be correct.

2. **Interface-level Administrative Access is a separate permission gate from firewall policy**, and it's easy to overlook because it's not where you'd normally look first. Hit on PING (twice) and SNMP (twice) across this project.

3. **Verify saved/persisted state, not just currently-working state.** `show startup-config` vs `show running-config`, or actually `cat`-ing a file after a script writes it, rather than assuming a paste or a save landed correctly. This exact gap caused a full SSH reconfiguration to be lost once in this project.

4. **Abbreviated config views can hide the actual problem.** FortiGate's `show X` vs `show full-configuration X` is a recurring, important distinction — the cipher conflict in Part 11 was completely invisible in the abbreviated view.

5. **A test or check that's never been proven to fail is not a trustworthy test.** The isolation-check script (Part 15/16) and the packet-capture evidence (Part 17) both reflect the same underlying discipline: validate against a real, deliberately-introduced fault before trusting a "looks good" result.

6. **When something looks like it could be serious, verify scope with an independent test before reacting — don't panic, and don't dismiss it either.** The DNS filter incident during deployment is the clearest example: a genuinely concerning signal (one IP answering for many unrelated domains, across independent resolvers) was investigated calmly and methodically, using an unrelated device to get a fast, clean answer about blast radius, before concluding what was actually happening.
