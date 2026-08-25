# Architecture — Cherwood Health

This document explains the network's design: the IP scheme, the VLAN plan, why each segment exists, and how traffic actually flows between zones.

---

## Design philosophy

Every segment in this network exists because a real organization would need it, not because "more VLANs looks impressive." A regional healthcare clinic group needs to separate staff systems from public WiFi, keep servers away from general traffic, isolate anything internet-facing, and give a satellite branch office internet access without blanket trust into headquarters. That's the shape this network takes.

## Topology overview

```
                              INTERNET
                                 │
                          [Verizon Router]
                          (ISP modem/router,
                           port-forward: 10443→FortiGate)
                                 │
                          ┌──────┴──────┐
                          │  FortiGate  │  wan1
                          │    60E      │
                          │ (Firewall/  │
                          │  Core GW)   │
                          └──────┬──────┘
                    internal1    │    internal2
                          │      │      │
              ┌───────────┘      │      └───────────┐
              │                  │                   │
      ┌───────┴────────┐         │           ┌───────┴────────┐
      │  Cisco 3560E    │         │           │  Cisco 1921    │
      │  (Core Switch)  │         │           │  (Branch       │
      │  Trunk: VLANs   │         │           │   Router)      │
      │  10,20,30,40    │         │           │  Transit link: │
      └───┬────┬────┬───┘         │           │  10.10.99.0/30 │
          │    │    │             │           └───────┬────────┘
       VLAN10 VLAN20 VLAN30       │                   │
      (Trusted)(Guest)(Servers)   │              10.20.0.0/24
          │    │    │             │              (Branch LAN)
      [Staff] [Guest [Proxmox/    │                   │
       AP]    AP]    T14 host]    │             [TP-Link AP]
                                  │
                             VLAN40 (DMZ)
                                  │
                          [cherwood-dmz container]
                                  │
                        Cloudflare Tunnel (outbound only)
                                  │
                       https://cherwood.tarunc.com
                          (public internet)
```

## IP addressing scheme

| Segment | Subnet | Gateway | Purpose |
|---|---|---|---|
| VLAN 10 — Trusted | `10.10.10.0/24` | `10.10.10.1` | Staff devices, admin access to network gear |
| VLAN 20 — Guest | `10.10.20.0/24` | `10.10.20.1` | Public/guest WiFi, isolated, bandwidth-capped |
| VLAN 30 — Servers | `10.10.30.0/24` | `10.10.30.1` | Proxmox host and all internal service containers |
| VLAN 40 — DMZ | `10.10.40.0/24` | `10.10.40.1` | Internet-facing services only |
| Branch transit link | `10.10.99.0/30` | FortiGate: `.1`, 1921: `.2` | Point-to-point HQ↔Branch routing link |
| Branch LAN | `10.20.0.0/24` | `10.20.0.1` (on the 1921) | Branch office's own local network |
| Default hardware switch (unused) | `10.99.99.0/24` | `10.99.99.1` | Legacy default FortiGate LAN ports, not used for anything active |
| SSL-VPN client pool | `10.212.134.200–210` | — | Addresses handed to remote VPN clients (default FortiGate range — see note in troubleshooting log re: planned migration to `10.10.50.0/24`) |

**Design note on the `/30` transit link:** a `/30` subnet mask provides exactly 2 usable host addresses — the minimum needed for a point-to-point link between exactly two routers. Using a full `/24` here would waste 252 unusable addresses for no benefit; this is standard practice for any router-to-router link.

## VLAN-by-VLAN breakdown

### VLAN 10 — Trusted
**Who's on it:** staff devices, and anyone managing the network itself (FortiGate admin, switch admin, monitoring dashboard access all happen from here).
**What it can reach:** the internet, Servers (VLAN 30) — legitimate need to reach internal services like the monitoring dashboard.
**What's denied to it:** nothing outbound is restricted; this is the most-trusted segment in the design.

### VLAN 20 — Guest
**Who's on it:** any public/visitor WiFi device.
**What it can reach:** the internet only, subject to DNS filtering (malware/phishing categories blocked) and a shared 10 Mbps bandwidth cap.
**What's explicitly denied:** Trusted (VLAN 10) and Servers (VLAN 30) — enforced by dedicated DENY policies (`Guest_to_Trusted_DENY`, `Guest_to_Servers_DENY`), not just relying on default-deny. This is intentional belt-and-suspenders design: an explicit, logged DENY policy is more auditable and more resilient to accidental future changes than relying purely on the absence of an ACCEPT rule.

### VLAN 30 — Servers
**Who's on it:** the Proxmox host and every internal-service container running on it — the monitoring stack (Prometheus/Grafana/exporters), the Kindle/RSS digest pipeline (`kindle-digest`, `knowledge-feed`).
**What it can reach:** the internet (needed for package updates, external API calls, SMTP for the digest pipeline), and — as of the monitoring work in Part 14 — Trusted (VLAN 10) and the Branch transit link, specifically so the monitoring container can query the FortiGate, switch, and Branch router via SNMP/SSH.
**Design tension worth noting honestly:** Servers having a path into Trusted and into Branch is a deliberate, narrow exception carved out specifically for monitoring/management traffic — not a blanket opening. In a stricter production design, this might instead be a dedicated, separate "Management" VLAN distinct from general Servers, so that a compromised general-purpose server container doesn't inherit management-plane reach. This tradeoff is flagged here explicitly as a reasonable lab simplification, not something accidentally overlooked.

### VLAN 40 — DMZ
**Who's on it:** exactly one container, hosting the public Cherwood Health demo site.
**What it can reach:** the internet only (for the outbound Cloudflare Tunnel connection and routine package updates), subject to the same DNS filtering as Guest.
**What's explicitly denied:** everything else. DMZ has no legitimate reason to reach Trusted, Guest, Servers, or Branch — and it doesn't. This was proven, not just configured — see the Part 17 packet-capture evidence in the troubleshooting log.
**Why it's exposed to the internet at all:** this is genuinely the point of a DMZ — a segment expected to be internet-facing, kept deliberately isolated from everything else so that if it's ever compromised, the blast radius is contained to that one segment.

### Branch Office (routed, not switched)
**Who's on it:** any device connected to Branch's WiFi (via TP-Link) or wired into the 1921's LAN side.
**What it can reach:** the internet only, routed back through HQ's FortiGate.
**What's explicitly denied:** all of HQ's internal VLANs (`Branch_to_HQ_DENY`) — Branch is treated as an untrusted network relative to HQ, the same posture as Guest.
**Why routing (RIP) instead of just another VLAN:** Branch is a physically separate site in the real-world scenario this project models — a satellite office, not another room in the same building. A routed link with its own router (the 1921) and its own subnet is the realistic architecture for that; VLANs are for segments on the same physical LAN.

## Public-facing exposure — the complete list

This network deliberately minimizes what's reachable from the raw internet. As of the current build, exactly two things are internet-facing:

1. **`https://cherwood.tarunc.com`** — the public demo site, served via **Cloudflare Tunnel** from the DMZ container. Notably, this involves **zero open inbound ports** on the home router/firewall — the tunnel is an outbound-only connection initiated by the DMZ container to Cloudflare's edge, meaning there's nothing for an internet scanner to even find and probe directly.
2. **SSL-VPN on port `10443`** — a single authenticated login gateway, forwarded from the ISP router directly to the FortiGate. This is the only genuinely open inbound port in the entire design.

Everything else — the FortiGate admin panel, the Grafana dashboard, Proxmox's own web UI, every internal service — is reachable only from inside the network (or through the SSL-VPN, once authenticated).

## Remote access design

Two independent remote-access mechanisms exist, deliberately kept separate:

1. **SSL-VPN** (FortiGate) — full network-level remote access, authenticated, tested from real cellular data. Fronted by DuckDNS dynamic DNS so the connection stays reachable even if the home ISP rotates the public IP.
2. **Tailscale** — a separate, narrower mesh-VPN connection specifically between one authorized phone and the `knowledge-feed` container, for convenient access to that one service without needing the full SSL-VPN tunnel.

**Worth noting as a real design consideration:** having two independent remote-access paths is a legitimate choice (different tools for different scopes of access), but it's also two separate attack surfaces to keep in mind — a fact that became directly relevant during SSL-VPN troubleshooting, when Tailscale running concurrently on a test device turned out to be interfering with the SSL-VPN connection itself (full story in the troubleshooting log).

## Monitoring architecture

```
FortiGate ──┐
3560E ──────┼── SNMP (v2c, read-only) ──► SNMP Exporter ──► Prometheus ──► Grafana
1921 ───────┘                             (10.10.30.10)     (scrapes      (dashboards)
                                                              every 15s)
knowledge-feed ── Node Exporter (host metrics) ────────────►┘
monitoring container ── Node Exporter (self) ───────────────►┘
```

All three core network devices (FortiGate, switch, Branch router) are polled via SNMPv2c every 15 seconds. Host-level metrics (CPU, memory) come from Node Exporter running directly on two containers. Everything is visualized in a single Grafana dashboard, "Cherwood Network Overview."

**Scope decision:** the HQ access point is not directly SNMP-monitored — its throughput is visible indirectly through the switch port it's connected to, which is monitored. This was a deliberate tradeoff (documented in the troubleshooting log) rather than pursuing uncertain Autonomous-mode SNMP support on that specific hardware.

## Automation architecture

```
Monitoring container (cron, nightly at 2:00–2:15 AM)
    ├─ 2:00 → backup-1921.sh       (SSH key auth, pulls running-config)
    ├─ 2:05 → backup-switch.sh     (SSH key auth, pulls running-config)
    ├─ 2:10 → backup-fortigate.sh  (SSH key auth, pulls full-configuration)
    └─ 2:15 → isolation-check.sh   (parses FortiGate backup, verifies
                                     3 key DENY policies are present,
                                     enabled, and correctly configured)
```

Each backup script saves a timestamped snapshot and diffs it against the previous run, logging exactly what changed (or confirming nothing did). The isolation-check script is a form of automated configuration-drift detection specifically for the security-critical segmentation policies — see the troubleshooting log for how this script's own logic was validated against a real, deliberately-introduced fault.

## Hardware substitution — Branch access point

**Planned:** a second Autonomous-mode Cisco access point for Branch, matching the HQ deployment.

**Actual:** the unit available for Branch turned out to be an `AIR-CAP3502I-A-K9` running **Lightweight/CAPWAP firmware** (confirmed via boot log analysis — the `K9W8` image designation, and repeated `%CAPWAP-3-DHCP_RENEW: Could not discover WLC` messages showing the AP actively searching for a Wireless LAN Controller this project doesn't have). Compounding this, the unit's console login credentials — inherited from its apparent former life as secondhand IT-training-lab equipment (boot log hostname: `AD_ITTECHLAB`) — could not be recovered within the scope of this session.

**Resolution:** a TP-Link Archer AX21 (already used successfully as an interim device earlier in the project) was deployed as Branch's practical access point. This introduces one architectural wrinkle worth naming explicitly: **double-NAT**. Branch clients connect to the TP-Link's own private subnet, which is then itself NAT'd again onto the `10.20.0.0/24` network at the TP-Link's WAN interface, before finally being NAT'd a third time at the FortiGate for internet-bound traffic. A "clean" enterprise deployment would avoid stacking NAT layers this way; this is a direct, honestly-documented consequence of substituting a consumer router/AP combo for what was meant to be a plain Autonomous-mode AP with no NAT of its own.

## Public web presence architecture

Two independent public sites are hosted on the same DMZ container, distinguished by port and Cloudflare Tunnel ingress routing rather than separate infrastructure:

```
Internet
   │
Cloudflare Edge (TLS termination, DDoS protection)
   │
   ├── tarunc.com / www.tarunc.com ──┐
   │                                  │
   └── cherwood.tarunc.com ──────────┤
                                      │
                          Cloudflare Tunnel (outbound-only
                          from cherwood-dmz, zero inbound ports)
                                      │
                          nginx on cherwood-dmz (10.10.40.2)
                                      │
                   ┌──────────────────┴──────────────────┐
                   │                                       │
          port 80: /var/www/html                 port 8081: /var/www/portfolio
          (Cherwood Corporation site)             (personal portfolio site)
```

**Why one container, two sites, rather than two separate containers:** both are static HTML with no backend, no database, and near-zero resource footprint — splitting them across separate containers would add operational overhead (two things to patch, two things to monitor) without a corresponding security or reliability benefit, since both sites carry the same (low) risk profile. Port-based separation within one nginx instance is a standard, appropriate pattern for this scale.

**DNS filter dependency, worth knowing explicitly:** the DMZ's outbound DNS filter (`Guest_DMZ_Filter`, originally built in Part 10.6) governs what domains the Cloudflare Tunnel client itself can resolve — including Cloudflare's own API and tunnel-protocol domains. This created a real, non-obvious failure mode during the portfolio site's deployment (full story in the troubleshooting log): a security control built to protect the DMZ from reaching malicious external sites can, if its allow-list isn't kept current, also block the DMZ's own legitimate outbound infrastructure dependencies. Any future service added to this container that needs its own external API access should be checked against this filter proactively, rather than discovered reactively.



Documenting this honestly, since a portfolio project should be clear about lab-vs-production differences:

- **SSL-VPN's self-signed certificate** would be replaced with a properly CA-signed certificate (e.g., via Let's Encrypt), avoiding client-side trust warnings.
- **SSL-VPN itself** is noted by Fortinet's own current guidance as a legacy option relative to IPsec VPN or ZTNA, given a real history of critical CVEs in SSL-VPN implementations across the industry. This is flagged as planned future work rather than an oversight — reasonable for a no-real-data lab environment to defer, not reasonable for a production deployment handling real data.
- **The Servers VLAN's reach into Trusted and Branch for monitoring purposes** would likely be split into a dedicated Management VLAN in a stricter design, so general-purpose service containers don't inherit management-plane network reach.
- **The double-NAT at Branch** would be resolved by replacing the TP-Link with a proper Autonomous-mode AP (recovering or replacing the original hardware).
- **SSH automation keys** use no passphrase, appropriate for this lab's unattended cron use case but worth pairing with additional controls (a bastion host, secrets management, IP-restricted access) in a real production environment.
