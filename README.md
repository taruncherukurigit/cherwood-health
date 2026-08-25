# Cherwood Health — Enterprise Network & Security Portfolio Project

**A fictional multi-site healthcare organization, built on real enterprise hardware — not simulated, not Packet Tracer, not a lab template.**

This project documents the design, build, and hardening of a segmented enterprise network for "Cherwood Health," a fictional regional clinic group with a headquarters site and a branch office. It was built end-to-end on physical Fortinet and Cisco hardware, with every design decision, bug, and fix documented honestly — including the ones that didn't go smoothly the first time.

> 📄 Full command-by-command reference: [`docs/COMMAND-REFERENCE.md`](docs/COMMAND-REFERENCE.md)
> 🐛 Real troubleshooting log (every bug, every fix): [`docs/TROUBLESHOOTING-LOG.md`](docs/TROUBLESHOOTING-LOG.md)
> 🚀 Deployment log (getting the sites live): [`docs/DEPLOYMENT-LOG.md`](docs/DEPLOYMENT-LOG.md)
> 🏗️ Architecture & design rationale: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
> 🎤 Interview prep — talk-track for every part: [`docs/INTERVIEW-PREP.md`](docs/INTERVIEW-PREP.md)
> 🌐 Live project site: [cherwood.tarunc.com](https://cherwood.tarunc.com)
> 💼 Personal portfolio: [tarunc.com](https://tarunc.com)
> 📦 This repo: [github.com/taruncherukurigit/cherwood-health](https://github.com/taruncherukurigit/cherwood-health)

---

## Why this project exists

Most portfolio projects in this space are simulated (GNS3, Packet Tracer) or a single flat network with a couple of VLANs. This project was built specifically to demonstrate:

- **Real hardware, real constraints** — actual Fortinet and Cisco gear, including legacy IOS versions with real compatibility quirks that don't show up in a simulator
- **Segmentation that's actually enforced and actually tested** — not just configured and assumed to work, but proven with real traffic, real logs, and in one case a live packet capture
- **Believable, honest engineering** — hardware that didn't work as planned was documented as a real constraint and worked around, not hidden
- **The full lifecycle** — not just "set it up," but monitored it, automated its backups, attacked it (safely, on purpose), and hardened it further

## What's actually in this network

| Layer | What's built |
|---|---|
| **Perimeter / Firewall** | FortiGate 60E — core gateway, all inter-VLAN policy enforcement, SSL-VPN remote access, RIP routing to Branch |
| **Core Switching** | Cisco Catalyst 3560E (PoE) — VLAN trunking, four segmented VLANs |
| **Segmentation** | 4 VLANs: Trusted (staff), Guest (public WiFi, bandwidth-capped and isolated), Servers (internal services), DMZ (public-facing) |
| **Branch Office** | Cisco 1921 ISR — routed site-to-site link to HQ via RIPv2, its own isolated LAN, internet-only by policy |
| **Remote Access** | SSL-VPN over a non-default port, dynamic DNS (DuckDNS), tested from real cellular data |
| **Monitoring** | Prometheus + Grafana + SNMP Exporter + Node Exporter — live dashboards for every network device |
| **Automation** | Nightly config backups (with diffing) and automated firewall-policy isolation checks for all three core devices |
| **Public Presence** | A real, internet-facing demo site (`cherwood.tarunc.com`) served through Cloudflare Tunnel from the DMZ, with zero open inbound ports |
| **Security Validation** | A real, deliberate reconnaissance simulation from the DMZ against the Trusted VLAN, confirmed blocked via live packet capture on the firewall |

## Screenshots

**Grafana dashboard** — live throughput monitoring for the FortiGate, Branch router, and core switch.

![Grafana dashboard 1](screenshots/grafana-dashboard1.png)
![Grafana dashboard 2](screenshots/grafana-dashboard2.png)
![Grafana dashboard 3](screenshots/grafana-dashboard3.png)

**FortiGate firewall policies** — the full segmentation policy set, every zone's access explicitly allowed or denied.

![FortiGate policies 1](screenshots/fortigate1.png)
![FortiGate policies 2](screenshots/fortigate2.png)

**FortiGate live traffic evidence** — Forward Traffic log and interface list, proving the segmentation is enforced in real time, not just configured.

![FortiGate forward traffic](screenshots/fortigateforwardtraffic.png)
![FortiGate interfaces](screenshots/fortigateinterfaces.png)

**Core switch** — VLAN database and trunk status, confirming the real 802.1Q design.

![Switch VLANs and trunk status](screenshots/switch.png)

**Branch router (1921)** — RIP-learned routes and interface status, proving dynamic site-to-site routing actually works.

![Branch router RIP routes and interfaces](screenshots/routeripinterfacebrief.png)

**HQ access point** — the dual-SSID, dual-radio wireless configuration.

![Access point SSID configuration](screenshots/ap.png)

**Automation in action** — a real backup script run and the live cron schedule driving it nightly.

![Backup script output](screenshots/backup-script-output.png)
![Cron schedule](screenshots/crontab.png)

**Proxmox** — the container fleet and network configuration behind the whole stack.

![Proxmox containers](screenshots/proxmoxcontainer.png)
![Proxmox DMZ container network config](screenshots/dmzproxmox.png)

**Cherwood Corporation project site** — live at cherwood.tarunc.com.

![Cherwood site live 1](screenshots/cherwood.tarunc.com.png)
![Cherwood site live 2](screenshots/cherwood.tarunc.com2.png)

**Personal portfolio site** — live at tarunc.com.

![Portfolio site live 1](screenshots/tarunc.com.png)
![Portfolio site live 2](screenshots/tarunc.com2.png)

## Physical build

Real hardware, not simulated — the actual devices, cabling, and lab setup behind this project.

![Physical build 1](screenshots/lab1.png)
![Physical build 2](screenshots/lab2.png)
![Physical build 3](screenshots/lab4.png)
![Physical build 4](screenshots/lab5.png)
![Physical build 5](screenshots/lab6.png)
![Physical build 6](screenshots/lab8.png)
![Physical build 7](screenshots/lab10.png)

## The hardware

| Device | Role |
|---|---|
| FortiGate 60E | Firewall / core router |
| Cisco Catalyst 3560E-24PD-S (PoE) | HQ core switch |
| Cisco 1921 ISR | Branch office router |
| Cisco Access Points (Autonomous mode) | HQ wireless |
| TP-Link Archer AX21 | Branch wireless (see note below) |
| Lenovo T14 running Proxmox | Homelab host — all monitoring/automation containers |

**Honest note on hardware substitution:** the access point originally planned for the Branch office turned out, on inspection, to be running Lightweight/CAPWAP firmware with unrecoverable secondhand credentials — not Autonomous mode as expected, and not usable without a Wireless LAN Controller this project doesn't have. Rather than force a bad fit or quietly swap it without mention, this is documented as a real hardware constraint: **the TP-Link fills in as Branch's access point**, and the diagnosis process (reading boot logs, identifying the firmware family, attempting password recovery) is documented in full in the troubleshooting log. This kind of pragmatic, honestly-documented substitution is closer to how real infrastructure work actually goes than a project where everything works perfectly on the first try.

## Skills demonstrated

`VLAN segmentation` `firewall policy design` `SSL-VPN` `dynamic DNS` `Cisco IOS routing (RIP)` `inter-site connectivity` `SNMP monitoring` `Prometheus & Grafana` `Bash scripting & automation` `SSH key management` `Cloudflare Tunnel` `traffic shaping / QoS` `network reconnaissance & detection` `packet capture analysis` `config drift detection` `cron scheduling` `Linux administration (Debian, LXC)` `Proxmox virtualization`

## Repository structure

```
cherwood-health/
├── README.md                          ← you are here
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md                ← network design, VLAN plan, IP scheme, diagrams
│   ├── COMMAND-REFERENCE.md           ← every command used, explained
│   ├── TROUBLESHOOTING-LOG.md         ← every real bug, root cause, and fix
│   ├── DEPLOYMENT-LOG.md              ← the site-launch DNS filter incident, in full
│   └── INTERVIEW-PREP.md              ← Q&A walkthrough for talking through this project
├── configs/
│   ├── fortigate/                     ← sanitized FortiGate config, real values verified
│   ├── cisco-1921/                    ← sanitized Branch router config (real device pull)
│   ├── cisco-3560e/                   ← sanitized switch config (real device pull)
│   └── cisco-ap/                      ← sanitized HQ access point config (real device pull)
├── scripts/
│   ├── README.md                      ← setup instructions
│   ├── backup-1921.sh
│   ├── backup-switch.sh
│   ├── backup-fortigate.sh
│   └── isolation-check.sh
├── site/
│   ├── index.html                     ← the Cherwood Corporation site, live at cherwood.tarunc.com
│   └── tarunc-root.html               ← personal portfolio, live at tarunc.com
└── screenshots/
    └── (dashboard, firewall policies, live sites, physical hardware — see below)
```

## A note on scope and honesty

This is a lab environment — no real patients, no real compliance load, no real attacker. Where design decisions were made for pragmatic lab reasons rather than "true" enterprise practice (double-NAT on the Branch AP substitution, a self-signed VPN certificate, etc.), that's called out explicitly rather than glossed over. The value of this project isn't that it's flawless — it's that every constraint, bug, and tradeoff is documented as it actually happened, which is a far more realistic picture of network engineering work than a project where nothing ever goes wrong.

---

*Built by Tarun Cherukuri as a hands-on portfolio project alongside CCNA study. See [`docs/INTERVIEW-PREP.md`](docs/INTERVIEW-PREP.md) for a full walkthrough of the technical decisions and troubleshooting behind this build.*
