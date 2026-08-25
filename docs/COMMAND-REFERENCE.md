# Command Reference — Cherwood Health

This document explains **every command used in this project**, organized by part, with what it does, why it was used, and what to watch out for. The goal is that you could read this cold and understand not just *what* was typed, but *why*, well enough to explain it in an interview or adapt it to a different environment.

**Coverage:** this document now covers Parts 0 through 18 in full, reconstructed from the actual build sessions — every command, every real bug, every fix.

---

## Table of Contents
1. [Part 0 — Domain & DNS Setup](#part-0)
2. [Parts 1-3 — Physical Wiring & FortiGate Foundation](#parts-1-3)
3. [Part 4 — VLANs & Branch Link on the FortiGate](#part-4)
4. [Part 5 — Switch-Side VLANs & Trunking](#part-5)
5. [Part 6 — Wireless SSID Configuration](#part-6)
6. [Part 7 — Firewall Policies](#part-7)
7. [Part 8 — Captive Portal](#part-8)
8. [Part 9 — Segmentation Testing](#part-9)
9. [Part 10 — Production Migration & DMZ](#part-10)
10. [Part 11 — SSL-VPN Remote Access](#part-11)
11. [Part 12/13 — Branch Office Routing](#part-1213)
12. [Part 14 — Monitoring (Prometheus/Grafana/SNMP)](#part-14)
13. [Part 15/16 — Automation (Backups & Isolation Checks)](#part-1516)
14. [Part 17 — Simulated Attack & Detection](#part-17)
15. [Part 18 — Guest Bandwidth Limiting](#part-18)

---

<a name="part-0"></a>
## Part 0 — Domain & DNS Setup

**What was done:** registered `tarunc.com` through Spaceship, then pointed its nameservers at Cloudflare (`bryce.ns.cloudflare.com` / `marissa.ns.cloudflare.com`) rather than using the registrar's own DNS. This decision was made early, before any hosting existed, so DNS propagation would already be complete by the time Part 10.5 (the DMZ site) needed it — propagation can take anywhere from minutes to 24+ hours, and there's no reason to be blocked on it mid-build.

**Why Cloudflare specifically, not the registrar's built-in DNS:** Cloudflare provides free SSL/TLS termination, DDoS protection, and — critically for this project — **Cloudflare Tunnel**, which is what later lets the DMZ site go live with zero open inbound ports (see Part 10.5 / [`ARCHITECTURE.md`](ARCHITECTURE.md)).

**Brand structure decision:** rather than invent a new fictional company for every future homelab project, a parent holding company concept was established — **Cherwood Corporation** — with Cherwood Health as its first "division." This gives every future project (Pi-hole, self-hosted music streaming, whatever comes next) a reusable narrative container instead of a one-off backstory each time.

**Subdomain plan established at this stage:**
| Subdomain | Purpose |
|---|---|
| `tarunc.com` (root) | Personal portfolio/resume homepage |
| `cherwood.tarunc.com` | Cherwood Health public demo site (Part 10.5) |
| `docs.tarunc.com` | This project's documentation page |
| Future subdomains | Reserved for future Cherwood Corporation "divisions" as built |

**Deliberately excluded from this domain:** an unrelated personal content brand under a different pen name — kept fully separate from the professional/networking identity this domain represents. A small but real piece of judgment worth mentioning in an interview if it comes up: keeping unrelated personal projects cleanly separated from a professional portfolio.

---

<a name="parts-1-3"></a>
## Parts 1-3 — Physical Wiring & FortiGate Foundation

### Part 1 — Physical connections

No commands — this part is entirely physical cabling:
- Verizon router (ISP modem) → FortiGate `wan1`
- FortiGate `internal1` → Cisco 3560E switch (this becomes the VLAN trunk)
- FortiGate `internal2` → reserved for the Branch link (connected later, in Part 12/13)
- 3560E switch → PoE injector → HQ access point
- Laptop → any FortiGate `internal` port, for initial admin access

### Part 2 — FortiGate admin access

**Accessing the GUI for the first time:**
```
https://192.168.1.99
```
**What this is:** the FortiGate 60E's factory-default LAN IP. The browser will show a certificate warning (the FortiGate ships with a self-signed cert) — this is expected and safe to click through for initial setup.

**Default login:** username `admin`, password left blank. On first login, the FortiGate immediately forces a password change — this is a genuinely good default behavior (no device should ship with a permanently blank admin password), and the new password was set at this point.

### Part 3 — Splitting `internal1` and `internal2` out of the default hardware switch

**The problem this solves:** out of the box, all 7 internal LAN ports on the FortiGate are bundled into a single combined interface (a "hardware switch," typically named `internal` or `lan`). `internal1` (destined for the VLAN trunk) and `internal2` (destined for the Branch link) need to behave completely independently, which isn't possible while they're part of that bundle.

**Step-by-step (GUI-driven on this FortiOS version, no CLI needed for the split itself):**

1. **Network → Interfaces**, edit the `internal` hardware switch
2. **Disable DHCP Server** on it, if enabled (its current DHCP config becomes irrelevant once ports are pulled out)
3. **Delete any firewall policy referencing the `internal`/`lan` interface** — required, since FortiGate won't let you remove ports from a hardware switch while a policy still references it as a whole
4. Re-open the `internal` hardware switch, and in the **Interface Members** list, click the small **✕** next to `internal1` and `internal2` to remove them — leaving `internal3` through `internal7` still grouped together
5. Click **OK**

**Real bug hit here:** the laptop used for admin access was connected via one of the ports about to be removed from the bundle — clicking OK would have immediately cut off admin access. **Fix:** physically moved the laptop's cable to one of the remaining `internal3`-`internal7` ports *before* applying the change, keeping it on a port that stayed part of the still-functioning `10.99.99.1/24`-addressed group. (This same default hardware-switch subnet had itself been changed earlier, from the factory `192.168.1.99/24` to `10.99.99.1/24`, specifically to avoid an address conflict with the Verizon router's own DHCP range on `192.168.1.x` — a small but real example of checking for upstream subnet collisions before assuming a private range is safe to reuse.)

**Verifying the split worked:** after applying, `internal1` and `internal2` appear in the interface list as standalone entries with `0.0.0.0/0.0.0.0` (no IP yet — expected, since they get their real addresses in Part 4) rather than being grouped under the hardware switch.

---

<a name="part-4"></a>
## Part 4 — VLANs & Branch Link on the FortiGate

**Why this part exists:** each logical zone (Trusted, Guest, Servers, and later DMZ) needs its own VLAN interface — a distinct broadcast domain and IP range, even though all of them ride the same physical cable to the switch (`internal1`) via 802.1Q tagging.

**Creating each VLAN (GUI: Network → Interfaces → Create New → Interface), repeated for each zone:**

**VLAN 10 — Trusted:**
- Name: `VLAN10_Trusted`
- Type: VLAN, Interface: `internal1`, VLAN ID: `10`
- IP/Netmask: `10.10.10.1/255.255.255.0`
- DHCP Server: enabled, address range `10.10.10.10`–`10.10.10.254` (deliberately leaving `.2`–`.9` free for statically-assigned infrastructure, like the switch's own management IP configured in Part 5)

**VLAN 20 — Guest:**
- Name: `VLAN20_Guest`
- Type: VLAN, Interface: `internal1`, VLAN ID: `20`
- IP: `10.10.20.1/255.255.255.0`
- DHCP: enabled, full range (no special reservation needed — nothing in this zone needs a fixed address)

**VLAN 30 — Servers:**
- Name: `VLAN30_Servers`
- Type: VLAN, Interface: `internal1`, VLAN ID: `30`
- IP: `10.10.30.1/255.255.255.0`
- DHCP: enabled (unused until the Part 10 production migration)

**Branch transit link (`internal2` — not a VLAN, a direct physical/subinterface IP):**
- Edit `internal2` directly (not "Create New")
- IP: `10.10.99.1/255.255.255.252` — a `/30` mask, correct for a point-to-point link with only two routers on it (see [`ARCHITECTURE.md`](ARCHITECTURE.md) for why `/30` specifically)
- No DHCP (only ever one device — the Branch router — on the other end)

**CLI equivalent, useful for scripting/automation or verification** (the GUI actions above translate to this underlying config):
```
config system interface
    edit "VLAN10_Trusted"
        set ip 10.10.10.1 255.255.255.0
        set allowaccess ping https ssh
        set interface "internal1"
        set vlanid 10
    next
end
```
**What each `set` line does:**
- `set ip` — the interface's own address and subnet mask
- `set allowaccess` — the interface-level Administrative Access list (which management protocols are permitted **to the FortiGate's own IP on this interface**) — this is the same permission gate that caused real, repeated bugs later in the project (SNMP and PING both got silently blocked at this exact layer in later parts) and is worth understanding clearly now: it's separate from firewall policy, and controls whether the FortiGate itself will even respond to that protocol on that interface.
- `set interface` — which physical/parent interface this VLAN sits on top of
- `set vlanid` — the 802.1Q tag number

**Verifying a VLAN's config directly:**
```
show system interface VLAN10_Trusted
```

---

<a name="part-5"></a>
## Part 5 — Switch-Side VLANs & Trunking

**Why this part exists:** the FortiGate now knows about VLANs 10/20/30, but the 3560E switch has no idea yet — without matching VLAN configuration on the switch, 802.1Q-tagged traffic from the FortiGate has nowhere defined to go once it arrives.

**Creating the VLANs on the switch (console/SSH into the 3560E):**
```
enable
configure terminal
vlan 10
 name Trusted
vlan 20
 name Guest
vlan 30
 name Servers
exit
```
**What this does:** creates each VLAN as an actual database entry on the switch — a real object with a name, not just a number referenced somewhere else. This distinction mattered later: **VLAN 40 (DMZ) initially didn't work correctly even after being added to a trunk's allowed-VLAN list, because it had never been formally created here as its own database entry** — a genuinely easy-to-miss two-step process (create the VLAN, separately permit it on a trunk) that tripped up the DMZ rollout in Part 10.5.

**Configuring the FortiGate-facing trunk port** (carries all VLANs the FortiGate needs to route between):
```
interface gigabitethernet0/1
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
exit
```
**What each line does:**
- `switchport mode trunk` — puts this port into 802.1Q trunk mode, meaning it carries multiple VLANs' traffic simultaneously, each tagged with its VLAN ID
- `switchport trunk allowed vlan 10,20,30` — explicitly restricts which VLANs are permitted across this trunk — a security-relevant default-deny practice; without this, a trunk port defaults to carrying *all* VLANs, which is broader than necessary

**Configuring the AP-facing trunk port** (only needs the VLANs actual wireless clients use):
```
interface gigabitethernet0/2
 switchport mode trunk
 switchport trunk allowed vlan 10,20
exit
```
**Why this port's allowed list is narrower than the FortiGate-facing one:** the AP only ever needs to carry Trusted and Guest wireless traffic — it has no legitimate reason to see Servers VLAN traffic at all, so it's excluded here. This is the same "only permit what's actually needed" principle later applied to firewall policy design.

**Setting a switch management IP** (so the switch itself can be reached for administration, separate from any single VLAN's gateway):
```
interface vlan10
 ip address 10.10.10.2 255.255.255.0
exit
ip default-gateway 10.10.10.1
```
**What this does:** gives the switch itself a stable, reachable address (`10.10.10.2`) on the Trusted VLAN, with a default gateway pointing at the FortiGate — this is what later made SSH-based automation (Part 15/16 config backups) possible; without this, the switch would have no IP reachable for management at all.

**A real bug hit here — native VLAN mismatch:** trunk ports on both ends of a link must agree on which VLAN is the "native" (untagged) VLAN, or traffic can silently misroute or get dropped. This was diagnosed and corrected during this part — a classic, common trunk-configuration gotcha worth knowing to check for (`switchport trunk native vlan X` on both ends must match).

**Verifying trunk state:**
```
show interface trunk
```
**What to look for:** confirms trunk mode, encapsulation (`802.1q`), status (`trunking`, not `not-trunking`), and which VLANs are actually active on each trunk port — a genuinely useful single command for confirming a trunk is working as intended.

**Saving the switch config (critical, and a lesson repeated later in the project when it was forgotten on the 1921 router):**
```
write
```

---

<a name="part-6"></a>
## Part 6 — Wireless SSID Configuration

**Real hardware detour worth documenting honestly:** the access point originally sourced for this project (an AIR-AP2802I) turned out to require Cisco's Mobility Express licensing/controller mode to function as intended — a "Mobility Express licensing wall" that made it unusable for a simple standalone/Autonomous deployment. Rather than force it, an Autonomous-mode-confirmed replacement (an AIR-CAP3702I-A-K9) was sourced instead, with the original unit's issue documented as a real, honest hardware constraint rather than glossed over. **A TP-Link Archer AX21 was deployed as a temporary interim AP** at HQ during the gap, so that Parts 7-9 (firewall policy, captive portal, and full segmentation testing) could be validated live rather than blocked on shipping.

### Configuring VLAN subinterfaces on each radio

Autonomous Cisco APs use one physical radio interface per band (`Dot11Radio0` for 2.4GHz, `Dot11Radio1` for 5GHz), each of which needs its own VLAN subinterfaces to bridge wireless clients into the correct VLAN.

```
interface Dot11Radio0.10
 encapsulation dot1Q 10 native
 bridge-group 1
exit
interface Dot11Radio0.20
 encapsulation dot1Q 20
 bridge-group 2
exit
```
**What each line does:**
- `interface Dot11Radio0.10` — creates a subinterface tagged for VLAN 10 on the 2.4GHz radio
- `encapsulation dot1Q 10 native` — tags this subinterface as VLAN 10, and marks it as the **native** (untagged) VLAN for this radio — exactly one VLAN per trunk/radio should be marked native, matching the native VLAN convention used on the switch trunks
- `bridge-group N` — Cisco Autonomous APs use bridge groups to associate a wireless VLAN subinterface with its corresponding wired-side VLAN — each VLAN gets its own bridge-group number, consistent across both the wired and wireless sides of that VLAN

### Configuring encryption and SSIDs on the radio itself

```
interface Dot11Radio0
 encryption vlan 10 mode ciphers aes-ccm
 encryption vlan 20 mode ciphers aes-ccm
 ssid Cherwood-Staff
 ssid Cherwood-Guest
exit
```
**What each line does:**
- `encryption vlan X mode ciphers aes-ccm` — sets AES-CCMP (the strong, modern WPA2 cipher) for traffic on that specific VLAN — configured per-VLAN since a single radio can broadcast multiple SSIDs mapped to different VLANs, each potentially needing independent encryption settings
- `ssid` — attaches a previously-defined SSID profile (name, VLAN, security settings — created separately via `dot11 ssid <name>` config, not shown here) to this radio

**Verifying:**
```
show run interface Dot11Radio0
show dot11 associations
```

### Real bug: `guest-mode` conflict between the two SSIDs on one radio

**Symptom:** attempting to mark `Cherwood-Guest` as a broadcasting "guest" SSID (`guest-mode`, which controls whether the SSID is openly advertised in beacon frames vs. hidden) failed:
```
Dot11Radio1: Guest-ssid already existing on ssid Cherwood-Staff
```
**Root cause:** Cisco Autonomous APs allow only **one** SSID per radio to hold the `guest-mode` designation — a hard vendor limit, not a config mistake. `Cherwood-Staff` had claimed that slot on the radio first.

**Fix — split the SSIDs across the two separate radios instead of sharing one:**
```
! On Radio0 — remove Guest, keep only Staff
interface Dot11Radio0
 no ssid Cherwood-Guest
exit

! On Radio1 — remove Staff, keep only Guest
interface Dot11Radio1
 no ssid Cherwood-Staff
exit

! Now apply guest-mode to Guest, alone on its own radio
dot11 ssid Cherwood-Guest
 guest-mode
exit
```
**Result:** `Cherwood-Staff` broadcasts on Radio0 (2.4GHz) only, `Cherwood-Guest` broadcasts on Radio1 (5GHz) only — each with its own independent `guest-mode` slot, no conflict.

**Saving:**
```
end
write
```

---

<a name="part-7"></a>
## Part 7 — Firewall Policies

**Why this is the real security core of the project:** VLANs alone don't block anything — they're just separate broadcast domains. **Firewall policy is what actually enforces segmentation.** This part is where the network goes from "logically organized" to "actually defended."

**GUI path:** Policy & Objects → Firewall Policy → Create New, repeated for each policy:

**Trusted → Internet:**
- Name: `Trusted_to_Internet`
- Incoming: `VLAN10_Trusted`, Outgoing: `wan1`
- Source/Destination: `all`
- Action: **ACCEPT**, NAT: **enabled**

**Guest → Internet:**
- Name: `Guest_to_Internet`
- Incoming: `VLAN20_Guest`, Outgoing: `wan1`
- Source/Destination: `all`
- Action: **ACCEPT**, NAT: **enabled**

**Guest → Trusted (explicit block):**
- Name: `Guest_to_Trusted_DENY`
- Incoming: `VLAN20_Guest`, Outgoing: `VLAN10_Trusted`
- Source/Destination: `all`
- Action: **DENY**

**Guest → Servers (explicit block, prepping for the Part 10 migration before Servers even had real traffic on it):**
- Name: `Guest_to_Servers_DENY`
- Incoming: `VLAN20_Guest`, Outgoing: `VLAN30_Servers`
- Source/Destination: `all`
- Action: **DENY**

**Critical concept — policy evaluation order:** FortiGate evaluates firewall policies **top to bottom, first match wins**. Both DENY rules need to sit **above** any broader ACCEPT rule that could otherwise match the same traffic first — if a DENY rule sits below a matching ACCEPT rule, it will never actually be evaluated, since the engine stops at the first match. This was checked explicitly after creating all four policies, using the policy list's ordering/drag-to-reorder capability.

**Design principle established here, reused throughout the rest of the project:** explicit DENY policies were chosen over relying purely on FortiGate's implicit default-deny behavior. Both approaches technically block the traffic, but an explicit, named, loggable DENY policy is more auditable, more visible in a policy list review, and more resilient to a future engineer (or future-you) not immediately realizing why some traffic isn't working — it documents the isolation decision directly in the policy list itself.

---

<a name="part-8"></a>
## Part 8 — Captive Portal on Guest

**Why:** a public/guest WiFi network conventionally requires some form of click-through acknowledgment before granting access — both a legal/accountability practice and a realistic detail for the "clinic visitor WiFi" scenario this project models.

**GUI path:** edit the Guest VLAN interface (or SSID, depending on FortiOS version/menu layout) and set:
- **Security mode:** `Captive Portal`
- **Authentication portal:** `Local` — hosts the portal directly on the FortiGate itself, no external server dependency
- **User access:** `Allow all` — no restriction to specific pre-created guest accounts; matches a simple "accept terms and continue" pattern rather than requiring credentials
- **Redirect after Captive Portal:** `Original Request` — sends the guest on to whatever site they originally tried to visit, rather than a fixed landing page

**Session timeout — a global setting, not per-interface on this FortiOS version:**
**GUI path:** User & Authentication → Authentication Settings → Authentication Timeout, set to `1440` minutes (24 hours).

**Real troubleshooting note — portal appeared to stop showing on a second device:** after confirming the portal worked correctly on an initial test device, a second device connecting later didn't see the portal at all. **Root cause:** FortiGate's captive portal tracks authenticated sessions (by MAC address, for the duration of the session timeout) rather than challenging every single connection attempt — so a device that had previously passed the portal within the timeout window (even from an earlier, different test) would correctly skip it on a subsequent connection, which is expected behavior, not a bug. **Verification method:** checked the live authenticated-session list directly (User & Authentication → Firewall User Monitor) to confirm which devices were already marked authenticated, rather than assuming the portal itself was broken.

---

<a name="part-9"></a>
## Part 9 — Segmentation Testing (before touching production)

**Why this part exists as its own checkpoint, before Part 10:** Part 10 migrates real, currently-working production containers (the T14's Kindle/RSS pipeline) onto this newly-segmented network. Before taking that risk, the segmentation itself needed to be proven correct on a clean, low-stakes test basis.

**Tests run, in order:**
1. **Trusted device confirms normal internet access** — baseline sanity check
2. **Guest device confirms the captive portal appears**, and confirms internet access works normally *after* accepting it
3. **Guest device attempts to reach a Trusted-VLAN device directly** — confirmed blocked (connection refused/timeout, no response)
4. **Confirmed the block was actually logged**, not just silently dropped with no record:

**GUI path:** Log & Report → Forward Traffic, filtered/reviewed for the Guest→Trusted attempt, confirming a **Deny** entry against the `Guest_to_Trusted_DENY` policy specifically (not just a generic implicit-deny with no clear attribution).

**Why "confirm it's logged" matters as its own explicit test step, not just "confirm it's blocked":** a block with no evidence trail is much less useful for later incident review or troubleshooting than a block that's clearly attributed to a specific, named policy in the logs. This same "prove it, don't just assume it worked" discipline shows up repeatedly later in the project — most notably in the Part 15/16 isolation-check script, which was explicitly validated against a real fault rather than trusted on a single clean test run (see [`TROUBLESHOOTING-LOG.md`](TROUBLESHOOTING-LOG.md)).

---

<a name="part-10"></a>
## Part 10 — Production Migration & DMZ

### Migrating the T14/Proxmox host onto the Servers VLAN

**Physical/switch step:** moved the T14's Ethernet connection to a dedicated switch port, configured as an access port (or a trunk carrying VLAN 30/40, depending on whether the host needed to present multiple VLANs to its guest containers) on the Servers VLAN.

**Real bug hit here — the Kindle/RSS digest pipeline broke silently after migration.** No clear error message, just failure partway through the automated pipeline (fetch articles → assemble digest → convert to EPUB → email to Kindle).

**Diagnosis — root-caused via `journalctl` on the receiver container, not guessed:**
```
journalctl -u <receiver-service-name> -f
```
**What this showed:** the newly-created Servers VLAN had **no outbound-to-internet firewall policy at all** — the containers could reach each other locally on the same VLAN, but had zero path to the actual internet. This single missing policy manifested as several *seemingly* unrelated failures simultaneously (DNS resolution failing, the RSS fetch step failing, outbound SMTP delivery failing) — all stemming from the exact same root cause, which wasn't obvious until traced back through the actual service logs rather than treated as three separate bugs.

**Fix:**
- Name: `Servers_to_Internet`
- Incoming: `VLAN30_Servers`, Outgoing: `wan1`
- Action: **ACCEPT**, NAT: **enabled**

**Verification, in order — each step building confidence before moving to the next:**
```
ping -c 4 8.8.8.8        ! confirms raw internet reachability
nslookup smtp.gmail.com  ! confirms DNS resolution now works (it was never actually a DNS-specific bug — fixing the underlying connectivity fixed DNS resolution automatically, since DNS queries need an outbound path too)
```
Followed by a full, real end-to-end run of the actual pipeline (triggered via n8n), watching each workflow node complete successfully, and confirming a real digest arrived on the physical Kindle device.

### Locking in stable addressing — DHCP reservations

Once IPs were confirmed working, they were pinned via DHCP reservation so they wouldn't drift on a future reboot:

**GUI path:** Network → Interfaces → VLAN30_Servers → DHCP Server → (Reserve IP / MAC Reservation option)

| Device | Reserved at |
|---|---|
| Proxmox host | `10.10.30.2` |
| `kindle-digest` container | `10.10.30.3` |
| `knowledge-feed` container | `10.10.30.4` |

**Follow-up cleanup required after this:** any place a previous, now-stale IP (from the old flat pre-migration network) was hardcoded needed manual updating — specifically, an n8n workflow's Code node had the old IP hardcoded, and would have silently continued failing even after the firewall fix if this hadn't been caught and corrected.

**Scoping the Trusted→Servers policy down from "all" to specific ports**, once initial testing confirmed everything worked broadly:
- Trusted → Servers, limited to only the specific ports actually needed (e.g., 8080 for FreshRSS, 5678 for n8n, 8083 for Trilium, 8006 for Proxmox's own UI, 5000 for the Kindle receiver) rather than leaving it open to `ALL` services — a least-privilege refinement applied once the broader rule was proven to work correctly.

### Part 10.5 — The DMZ site (`cherwood.tarunc.com`)

**Creating VLAN 40 (DMZ) — same pattern as the other VLANs, riding the same physical FortiGate↔switch cable:**
```
! FortiGate side — Network → Interfaces → Create New
! Name: VLAN40_DMZ, Interface: internal1, VLAN ID: 40
! IP: 10.10.40.1/24, DHCP enabled
```

**Widening the existing switch trunk to include VLAN 40** (the exact two-step gotcha flagged in Part 5 — VLAN 40 needed to exist as a formal database entry *and* be added to the trunk's allowed list; initially only the second half was done, causing traffic to not pass correctly until both were confirmed):
```
enable
configure terminal
interface gigabitethernet0/1
 switchport trunk allowed vlan add 40
exit
write
```

**Creating a new, isolated LXC container on the T14** for the DMZ site specifically — deliberately kept separate from the existing production containers (`kindle-digest`, `knowledge-feed`), assigned to VLAN 40.

**Installing the web server:**
```bash
apt update && apt install -y nginx
systemctl status nginx
```

**Installing Cloudflare's tunnel client:**
```bash
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb
```

**Authenticating and creating a persistent, named tunnel** (deliberately not the ephemeral "Quick Tunnel" option, which generates a random, temporary URL each run — a named tunnel gets a permanent identity tied to the actual domain):
```bash
cloudflared tunnel login
cloudflared tunnel create cherwood-health-site
```
**What this does:** `login` opens a browser flow to authorize the tunnel against the Cloudflare account managing the domain; `create` provisions a tunnel with a permanent ID, independent of any one running process.

**Pointing the domain at the tunnel:**
```bash
cloudflared tunnel route dns cherwood-health-site cherwood.tarunc.com
```

**Tunnel config file (`~/.cloudflared/config.yml`):**
```yaml
tunnel: cherwood-health-site
credentials-file: /root/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: cherwood.tarunc.com
    service: http://localhost:80
  - service: http_status:404
```
**What this does:** maps the public hostname to the container's own local nginx instance (`localhost:80`), with a catch-all `404` rule for any other hostname that might reach this tunnel — standard Cloudflare Tunnel ingress convention.

**Real bug — the tunnel kept dying after apparently-successful manual tests.** Running `cloudflared tunnel run cherwood-health-site` directly in a foreground terminal session worked during the test itself, but the site would go dark again shortly after. **Root cause, confirmed via `ps aux | grep cloudflared` and the tunnel's own logs** (which explicitly showed `Initiating graceful shutdown due to signal interrupt`): a foreground process terminates the moment its controlling terminal session ends — a `Ctrl+C`, a disconnect, simply closing the console window.

**Fix — wrapped as a proper systemd service:**
```bash
cloudflared service install
systemctl start cloudflared
systemctl enable cloudflared
systemctl status cloudflared
```
**What this achieves:** a real background service that survives terminal disconnects, container reboots, and crashes (systemd restarts it automatically on failure) — the correct way to run any persistent network service, not just this one.

**Note on config file location:** `cloudflared service install` generates its own copy of the config at `/etc/cloudflared/config.yml`, a different path from where it was first manually created (`~/.cloudflared/config.yml`) — worth explicitly verifying the *actual* file being used by the running service matches intended content, rather than assuming the original file location is still authoritative once a service-install step has run.

### Part 10.6 — DNS filtering on Guest and DMZ

**Creating a shared DNS filter profile:**
**GUI path:** Security Profiles → DNS Filter → Create New
- Name: `Guest_DMZ_Filter`
- Categories blocked: Malicious Websites, Phishing, Spam URLs, Dynamic DNS, Newly Observed/Registered Domains (a category commonly abused by short-lived malicious domains), plus the broader "Potentially Liable" category group
- Botnet C&C redirect: enabled
- DNS query logging: enabled

**Attaching it to both relevant outbound policies** (`Guest_to_Internet` and `DMZ_to_Internet`) via each policy's Security Profiles section.

**Testing methodology worth understanding, not just the result:** an early test attempt (visiting a known-safe test-malware URL from a Guest device) produced an ambiguous result, since Guest traffic passes through *two* potential blocking mechanisms in sequence — the captive portal (session-level gate, evaluated first) and the DNS filter (content-level gate, evaluated only after the portal's already been passed). A block could plausibly have come from either one, or even the browser's own built-in safety features, making the test inconclusive.

**Fix — isolated the variable by testing from DMZ instead**, which has DNS filtering but *no* captive portal at all:
```bash
curl http://testsafebrowsing.appspot.com/s/malware.html
```
**Result:** the response came back as FortiGate's own literal block page (`Fortinet Secure DNS Service Portal — Web Page Blocked!`) — unambiguous, direct proof that the FortiGate's DNS filter itself was the mechanism intercepting the request, with no other variable in play.


<a name="part-11"></a>
## Part 11 — SSL-VPN Remote Access

### FortiGate: Enabling SSL-VPN

**GUI path:** VPN → SSL-VPN Settings

Key settings configured:
- **Listen on Interface(s):** `wan1` — the VPN listens on the internet-facing interface, since remote users connect from outside
- **Listen on Port:** `10443` — a **non-default** port, not the standard `443`. This is a deliberate, mild obfuscation step: it doesn't stop a targeted attacker, but it filters out the huge volume of automated internet-wide scanners that only check default ports
- **Server Certificate:** `Fortinet_Factory` (the FortiGate's built-in self-signed cert) — acceptable for a lab; a production deployment would use a real CA-signed cert (e.g., via Let's Encrypt) to avoid client-side trust warnings

### FortiGate CLI: Diagnosing the cipher conflict

```bash
show vpn ssl settings
```
**What it does:** Shows the current SSL-VPN configuration, but *only fields that differ from their default value*. This is important — it initially hid the real problem.

```bash
show full-configuration vpn ssl settings
```
**What it does:** Shows the *complete* configuration, including fields still at their default. This revealed the actual conflict:
```
set banned-cipher SHA1 SHA256 SHA384
set ciphersuite TLS-AES-128-GCM-SHA256 TLS-AES-256-GCM-SHA384 TLS-CHACHA20-POLY1305-SHA256
```
**The bug:** the configured cipher suite requires SHA256/SHA384, but those were simultaneously banned — leaving zero valid ciphers to negotiate. This caused every SSL-VPN connection attempt to fail with a generic, unhelpful "SSL exit error" before authentication was ever reached.

**Lesson:** when troubleshooting a config, always check the *full* configuration, not just the abbreviated view — the abbreviated view can hide the actual conflict.

```bash
config vpn ssl settings
    unselect banned-cipher SHA256
    unselect banned-cipher SHA384
end
```
**What it does:** Removes SHA256 and SHA384 specifically from the banned-cipher list, while correctly leaving SHA1 banned (SHA1 genuinely is weak and should stay excluded). `unselect` removes individual items from a multi-value field, as opposed to `unset` which would clear the entire field.

### FortiGate: Firewall policy for SSL-VPN traffic

**The core lesson of this whole part:** enabling a service (like SSL-VPN) does **not** automatically permit traffic through the firewall. FortiGate's policy engine evaluates every packet independently of whether the underlying service is "on."

**GUI path:** Policy & Objects → Firewall Policy → Create New
- **Name:** `SSLVPN_to_Trusted`
- **Incoming interface:** SSL-VPN tunnel interface (`ssl.root`)
- **Outgoing interface:** `VLAN10_Trusted`
- **Source:** `all` + specific user `tarun_vpn` (FortiGate requires an explicit user/group on SSL-VPN policies, not just an address)
- **Destination:** `all`
- **Action:** `ACCEPT`
- **NAT:** off (VPN traffic is already tunneled, doesn't need re-NAT'd)

### DuckDNS dynamic DNS updater (on DMZ container)

```bash
mkdir -p ~/duckdns
cat << 'EOF' > ~/duckdns/duck.sh
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=tarunhomelab&token=[REDACTED]&ip=" | curl -k -o ~/duckdns/duck.log -K -
EOF
chmod 700 ~/duckdns/duck.sh
```
**What it does:** Creates a script that calls DuckDNS's update API. The `&ip=` parameter is left blank, which tells DuckDNS to auto-detect and use the caller's own public IP — meaning this works correctly even behind NAT.

```bash
crontab -e
```
Then add:
```
*/5 * * * * ~/duckdns/duck.sh >/dev/null 2>&1
```
**What it does:** Runs the updater every 5 minutes via cron, keeping the DNS record current even if the home ISP rotates the public IP.

**Real bug hit here:** the DMZ's DNS/web filter (`Guest_DMZ_Filter`) initially blocked `duckdns.org` outright — FortiGuard's category database flags many DDNS providers as "Dynamic DNS" by default, since they're commonly abused for malware command-and-control. Fixed by adding an explicit **wildcard** allow entry (`*.duckdns.org`, not just the bare domain — the actual request goes to `www.duckdns.org`, which a non-wildcard entry wouldn't match).

### Verizon router: Port forwarding

Rule: `10443/TCP` (external) → `192.168.1.177:10443` (FortiGate's WAN-facing private IP, internal)

**Real bug hit here:** the rule appeared saved in the router's UI table, but had not actually been committed — confirmed via an external port-checker tool (yougetsignal.com) reporting the port closed even after the rule "looked" saved. **Lesson: UI state showing a rule in a table is not proof it was saved — verify with a hard refresh or, better, an external tool that tests the real-world result.**

### The root-cause bug: Tailscale interference

The dominant cause of the SSL-VPN connection failures turned out to be **Tailscale running in the background on the test phone**, conflicting with FortiClient's own VPN tunnel interface. Most mobile OSes can only cleanly route through one active VPN interface at a time. Disabling Tailscale on the phone was the step that took the error from a silent TLS failure to a real authentication prompt, and ultimately a working connection.

**Lesson:** when a client-side connection fails with no clear server-side cause, check for competing VPN/tunnel software on the client itself, not just server config.

---

<a name="part-1213"></a>
## Part 12/13 — Branch Office Routing

### Cisco 1921: Basic interface configuration

```bash
enable
configure terminal
hostname CherwoodBrand-1921
interface gigabitEthernet0/0
 description Link-to-HQ-FortiGate
 ip address 10.10.99.2 255.255.255.252
 no shutdown
exit
```
**What each line does:**
- `enable` — enters privileged EXEC mode (required for `configure terminal`)
- `configure terminal` — enters global configuration mode
- `hostname` — sets the device's name, shown in the CLI prompt and used in SNMP/logging
- `interface gigabitEthernet0/0` — enters interface configuration mode for that specific port
- `description` — a human-readable label, purely documentation, doesn't affect function but is genuinely useful for anyone reading the config later
- `ip address ... 255.255.255.252` — assigns an IP with a `/30` mask (only 2 usable addresses), the standard choice for a point-to-point link between exactly two routers
- `no shutdown` — **critical, easy to miss:** Cisco *router* interfaces (unlike switch ports) are administratively shut down by default out of the box. This command enables the interface. Forgetting this is one of the most common "why isn't this link coming up" mistakes on Cisco gear.

**Real bug hit here:** even after `no shutdown`, the link showed up physically but pings failed. Root cause: the FortiGate's `internal2` interface had **PING unchecked** under Administrative Access — an interface-level permission gate, separate from firewall policy, that silently drops ICMP even on a physically healthy link.

### FortiGate: Enabling PING on an interface

**GUI path:** Network → Interfaces → (select interface) → Administrative Access → check PING → Apply

This is a recurring pattern in this project: **FortiGate interfaces have their own Administrative Access permission list, independent of firewall policy.** SNMP, HTTPS, SSH, and PING all need to be explicitly enabled per-interface if that traffic needs to reach the FortiGate's own IP on that interface.

### RIP routing configuration

**On the 1921:**
```bash
router rip
 version 2
 network 10.10.99.0
 network 10.20.0.0
 no auto-summary
```
**What each line does:**
- `router rip` — enters RIP routing protocol configuration
- `version 2` — RIPv1 doesn't support subnet masks in its updates (it assumes classful boundaries) and is obsolete; always use v2
- `network X.X.X.X` — tells RIP which directly-connected networks to advertise to neighbors, and which interfaces to actually run RIP on. **Note:** Cisco IOS internally stores these as classful addresses — entering `10.10.99.0` and `10.20.0.0` both get folded into a single `network 10.0.0.0` entry when viewed later, since both fall within the same Class A block. This is normal IOS behavior, not a bug — the *advertised routes* still carry their real subnet masks correctly because of `no auto-summary`.
- `no auto-summary` — prevents RIP from collapsing advertised routes down to classful boundaries. Without this, your `/30` and `/24` subnets could get summarized incorrectly and break routing.

**On the FortiGate (CLI only — RIP isn't exposed in the GUI):**
```bash
config router rip
    config network
        edit 1
            set prefix 10.10.99.0 255.255.255.252
        next
        edit 2
            set prefix 10.10.10.0 255.255.255.0
        next
        edit 3
            set prefix 10.10.20.0 255.255.255.0
        next
        edit 4
            set prefix 10.10.30.0 255.255.255.0
        next
        edit 5
            set prefix 10.10.40.0 255.255.255.0
        next
    end
end
```
**What it does:** FortiGate's CLI uses a numbered-table editing pattern (`edit N` / `next`) rather than free-form lines. Each entry defines one network to advertise via RIP — here, the transit link plus all four HQ VLANs, so the Branch router learns routes to everything at HQ.

### Verifying RIP convergence

```bash
show ip route rip          ! (on the 1921)
get router info routing-table rip    ! (on the FortiGate)
```
**What they do:** Show routes specifically learned via RIP (as opposed to the full routing table, which includes connected/static routes too). Used to confirm each router actually learned the other side's networks.

### The missing default route

**Real bug:** after RIP converged correctly (both sides had learned each other's specific networks), the Branch router still couldn't reach the general internet (`ping 8.8.8.8` failed). **Root cause:** RIP only knows about the specific networks explicitly listed in its config — it has no concept of "everything else." Fixed with:

```bash
ip route 0.0.0.0 0.0.0.0 10.10.99.1
```
**What it does:** A static default route — "if you don't have a more specific route for a destination, send it here." `0.0.0.0 0.0.0.0` is the "match anything" network/mask pair. This tells the 1921 to forward any unrecognized destination to the FortiGate, which then handles actually getting it to the internet.

### Firewall policies for Branch traffic

```
Branch_to_Internet:   internal2 → wan1,  ACCEPT, NAT on
Branch_to_HQ_DENY:    internal2 → internal1,  DENY, logged
```
**Why both are needed:** a route existing in the routing table does not mean traffic is permitted through the firewall. `Branch_to_Internet` explicitly allows Branch clients out to the internet (with NAT, since Branch's private addressing needs to be translated to the public IP). `Branch_to_HQ_DENY` explicitly blocks Branch from reaching HQ's internal VLANs — mirroring the same isolation pattern already used for Guest, so Branch is treated as an untrusted network relative to HQ's Trusted/Servers segments.

### DHCP pool for the Branch transit link

**Real bug:** the TP-Link (acting as Branch's AP) got a private `192.168.x.x` address with no internet — its WAN port never received a real address from the 1921, because **no DHCP pool existed on the 1921 for that interface.**

```bash
ip dhcp pool BRANCH-WAN
 network 10.20.0.0 255.255.255.0
 default-router 10.20.0.1
 dns-server 8.8.8.8
exit
ip dhcp excluded-address 10.20.0.1 10.20.0.10
```
**What each line does:**
- `ip dhcp pool BRANCH-WAN` — creates a named DHCP pool
- `network` — the subnet this pool hands out addresses from
- `default-router` — the gateway address handed to clients (the 1921's own interface IP)
- `dns-server` — the DNS server handed to clients
- `ip dhcp excluded-address` — reserves a range (here, `.1` through `.10`) that DHCP will never hand out, keeping it free for static/infrastructure use (like the TP-Link itself, or future static devices)

```bash
show ip dhcp binding
```
**What it does:** Shows currently active DHCP leases — used to confirm the TP-Link actually picked up an address after the pool was created.

---

<a name="part-14"></a>
## Part 14 — Monitoring (Prometheus, Grafana, SNMP)

### Proxmox: Creating the monitoring container

```bash
pct create 103 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname cherwood-monitoring \
  --cores 2 --memory 2048 --swap 512 \
  --rootfs local-lvm:16 \
  --net0 name=eth0,bridge=vmbr0,ip=10.10.30.10/24,gw=10.10.30.1 \
  --unprivileged 1 --features nesting=1 --onboot 1
```
**What it does:** Creates a new LXC (Linux Container) on Proxmox — a lightweight virtualization method that shares the host kernel rather than emulating full hardware (faster and lighter than a full VM, at the cost of some isolation). Key flags:
- `--unprivileged 1` — runs the container without root-equivalent host access, a safer default
- `--features nesting=1` — allows running nested containers/Docker inside this container if ever needed
- `--net0 ... ip=.../24,gw=...` — static IP assignment at creation time, rather than relying on DHCP

**Note:** the CLI template download failed in this session with a filename mismatch; the container was created manually via the Proxmox web UI instead — a reasonable pragmatic call rather than debugging tooling further.

### Installing Prometheus

```bash
useradd --no-create-home --shell /bin/false prometheus
mkdir /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus
```
**What it does:** Creates a dedicated, non-login system user to run Prometheus — a security best practice (never run services as root unless genuinely required). `--no-create-home` and `--shell /bin/false` ensure this account can't be used to log in interactively.

```bash
wget https://github.com/prometheus/prometheus/releases/download/v2.53.0/prometheus-2.53.0.linux-amd64.tar.gz
tar xvf prometheus-2.53.0.linux-amd64.tar.gz
cp prometheus-2.53.0.linux-amd64/prometheus /usr/local/bin/
cp prometheus-2.53.0.linux-amd64/promtool /usr/local/bin/
```
**What it does:** Downloads the official Prometheus binary release, extracts it, and installs the two executables (`prometheus` itself, and `promtool` — a validation/query utility) into the system PATH.

**Prometheus config (`/etc/prometheus/prometheus.yml`):**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```
**What it does:** `scrape_interval` controls how often Prometheus polls each target for fresh metrics. This first job is Prometheus monitoring itself (a common, harmless self-referential pattern).

**Systemd service file (`/etc/systemd/system/prometheus.service`):**
```ini
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yml \
  --storage.tsdb.path /var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
```
**What it does:** Registers Prometheus as a proper Linux system service — starts automatically on boot, restarts if it crashes (with default systemd behavior), runs as the dedicated `prometheus` user, not root.

```bash
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
```
**What each does:** `daemon-reload` tells systemd to re-read service files after you've added/changed one. `enable` makes it start automatically on boot. `start` starts it right now.

### Installing Node Exporter (host metrics)

Same install pattern as Prometheus — download, extract, install binary, dedicated user, systemd service. Node Exporter exposes host-level metrics (CPU, memory, disk, network) on port `9100`, which Prometheus then scrapes.

**Installed on:** the monitoring container itself, and `knowledge-feed` (the Kindle/RSS pipeline container) — this is the one host specifically requested for monitoring per the project's scope.

### Installing SNMP Exporter

```bash
wget https://github.com/prometheus/snmp_exporter/releases/download/v0.26.0/snmp_exporter-0.26.0.linux-amd64.tar.gz
```
**What it does:** SNMP Exporter is a translator — it speaks SNMP to network devices (an old, clunky-but-universal protocol) and re-exposes that data in Prometheus's modern format. It ships with a large default `snmp.yml` containing MIB (Management Information Base) definitions for hundreds of vendors, including Fortinet and Cisco, so you don't need to hand-write SNMP OID mappings.

**Custom auth profile (added to `/etc/snmp_exporter/snmp.yml`):**
```yaml
auths:
  cherwood_v2:
    community: cherwood-monitoring
    version: 2
```
**What it does:** SNMP Exporter requires SNMP credentials to be defined as a *named profile* in its config file — you can't just pass a raw community string as a URL parameter. This defines a profile named `cherwood_v2` using SNMPv2c with the actual community string configured on the network devices.

### FortiGate: Enabling SNMP

**GUI path:** System → SNMP
- SNMP Agent: enabled
- SNMP v1/v2c community: name `cherwood-monitoring`, **v1 disabled, v2c enabled** (v2c is more standard/secure than the older v1)
- Hosts: `10.10.30.10/32` (only the monitoring container, not any other IP)
- Host Type: **"Accept queries only"** (the monitoring system pulls data; it never needs to receive traps for this setup)

**Real bug hit here:** SNMP queries from the monitoring container to `10.10.10.1` timed out even after the community was configured. Root cause: **SNMP was unchecked under `VLAN10_Trusted`'s Administrative Access** — same pattern as the PING issue in Part 12/13. Also required an additional firewall policy (`Servers_to_Trusted_Monitoring`, VLAN30→VLAN10, ACCEPT) since no policy previously existed for that direction — only the reverse (`Trusted_to_Servers`) had been created.

### Cisco (1921 and 3560E): Enabling SNMP

```bash
snmp-server community cherwood-monitoring RO
snmp-server location Cherwood-Branch
snmp-server contact tarun
```
**What each line does:**
- `snmp-server community ... RO` — sets the read-only community string. `RO` (read-only) vs `RW` (read-write) matters: RO means SNMP queries can only *read* device state, never change configuration — the correct, safer choice for a monitoring-only setup.
- `location` / `contact` — purely descriptive metadata fields, shown in SNMP queries and useful for documentation, no functional effect.

### Testing an SNMP query directly

```bash
curl "http://localhost:9116/snmp?target=10.10.10.1&module=if_mib&auth=cherwood_v2"
```
**What it does:** Manually triggers the SNMP Exporter to query a specific target right now (rather than waiting for Prometheus's scheduled scrape), using the `if_mib` module (a standard, vendor-agnostic module covering network interface statistics) and the named auth profile. Useful as a first, isolated test before wiring it into Prometheus's automated scrape config.

### Wiring SNMP into Prometheus's scrape config

```yaml
  - job_name: 'snmp_fortigate'
    static_configs:
      - targets:
        - 10.10.10.1
    metrics_path: /snmp
    params:
      module: [if_mib]
      auth: [cherwood_v2]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 10.10.30.10:9116
```
**What this does, in plain terms:** this is a relabeling trick that's genuinely worth understanding, not just copying. Prometheus normally scrapes a target directly at its listed address. But SNMP doesn't work that way — Prometheus needs to ask the *SNMP Exporter* to go query the *real device* on its behalf. The `relabel_configs` block rewrites the request so that:
1. The device's real IP (`10.10.10.1`) becomes a URL parameter (`?target=10.10.10.1`)
2. The `instance` label (used for display/grouping in Grafana) is set to the real device's IP, not the exporter's
3. The actual HTTP request Prometheus sends goes to the SNMP Exporter itself (`10.10.30.10:9116`), which then does the real SNMP work

This pattern (proxy-style scraping via relabeling) is standard for any Prometheus exporter that queries *other* devices on behalf of Prometheus (SNMP Exporter, Blackbox Exporter, etc.) — worth recognizing as a reusable concept, not just this one config block.

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"job"|"health"'
```
**What it does:** Queries Prometheus's own API for the current status of every configured scrape target, and filters the output down to just the job name and health status — a quick way to confirm everything is being scraped successfully (`"health": "up"`) without wading through Prometheus's full web UI.

### Installing Grafana

```bash
wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list
apt update
apt install -y grafana
systemctl enable grafana-server
systemctl start grafana-server
```
**What it does:** Adds Grafana's official APT repository (with its GPG signing key, so package integrity can be verified) and installs via the normal Debian package manager — the recommended install method, since it handles the systemd service setup automatically (unlike the manual binary installs used for Prometheus/exporters).

### Grafana query examples and what they mean

```promql
ifOutOctets{job="snmp_fortigate"}
```
Raw interface output-byte **counter** — a value that only ever increases (it resets only on device reboot). Graphed directly, this produces an ever-climbing staircase, not useful bandwidth data.

```promql
rate(ifOutOctets{job="snmp_fortigate"}[5m])
```
**The fix:** `rate()` calculates the *per-second average rate of increase* over the trailing 5-minute window, converting a raw counter into actual throughput (bytes/sec). This is the standard, correct way to graph any Prometheus counter metric — a pattern that applies far beyond just this project.

```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```
Calculates CPU usage percentage by taking the *idle* time rate (how much CPU was doing nothing) and subtracting from 100 — since CPU usage and idle time are complements of each other.

```promql
clamp_max((1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100, 100)
```
Memory usage percentage, wrapped in `clamp_max(..., 100)` to cap the displayed value at 100% — a practical fix for a known limitation where unprivileged LXC containers can report host-level (not container-level) memory figures via `/proc/meminfo`, occasionally producing nonsensical values above 100%.

---

<a name="part-1516"></a>
## Part 15/16 — Automation (Config Backups & Isolation Checks)

### Generating SSH keys for automation

```bash
ssh-keygen -t ed25519 -f /root/.ssh/cherwood_backup -N ""
```
**What it does:** Generates an SSH key pair using the modern Ed25519 algorithm. `-N ""` sets an empty passphrase — necessary for a key used in unattended automation (cron can't type a passphrase), but a real security tradeoff worth being able to explain: this key, if stolen, grants read access to device configs with no second factor. Mitigated by being a dedicated, narrowly-scoped key (not a personal login key) used only for this one automated purpose.

**Real bug:** the 1921 rejected this key entirely (`%SSH: Only ssh-rsa type is supported`) — its IOS version's SSH implementation doesn't support Ed25519. Required generating a second, separate key:

```bash
ssh-keygen -t rsa -b 2048 -f /root/.ssh/cherwood_backup_rsa -N ""
```
**What it does:** Generates an RSA 2048-bit key instead — older but universally compatible, the right choice when a target device's SSH stack doesn't support modern key types.

### Adding the public key to Cisco devices (1921, 3560E)

```bash
ip domain-name cherwoodbranch.local
crypto key generate rsa modulus 2048
ip ssh version 2
username admin privilege 15 secret [password]
line vty 0 4
 transport input ssh
 login local
exit
```
**What each line does:**
- `ip domain-name` — required before `crypto key generate rsa` will work; the domain name becomes part of the generated key's identity
- `crypto key generate rsa modulus 2048` — generates the device's own SSH **host key** (proves the device's identity to connecting clients) — different from the user's key pair, this is the router/switch's own key
- `ip ssh version 2` — explicitly enables SSHv2 (v1 has known security weaknesses)
- `username ... privilege 15 secret ...` — creates a local user account with full admin privilege (15 is the maximum), `secret` (not `password`) stores it as a proper one-way hash rather than reversible encryption
- `line vty 0 4` — enters configuration for the 5 virtual terminal lines (concurrent remote sessions)
- `transport input ssh` — only SSH is accepted on these lines (not Telnet, which is unencrypted)
- `login local` — authenticate against the local username database, not an external AAA server

**Adding the actual public key** (Cisco's `key-string` mode, entered via `ip ssh pubkey-chain`):
```bash
ip ssh pubkey-chain
username admin
key-string
[base64 key data, pasted as multiple ~64-character lines]
exit
exit
exit
end
```
**Critical, non-obvious detail:** Cisco IOS's `key-string` mode expects the **raw base64 key data only** — no `ssh-rsa` prefix, no `user@host` comment (the parts a standard `.pub` file includes). It also expects the data split across **multiple shorter lines**, not one giant line — pasting one very long unbroken line into a router console is unreliable and can silently corrupt/truncate. This was discovered the hard way, through repeated `%SSH: Failed to decode the Key Value` errors before switching to the correct chunked format.

```bash
write memory
```
**Critical, easy to forget:** saves the running configuration to NVRAM (non-volatile memory), so it survives a reboot. **This was skipped once in this project**, and a router reload between sessions wiped an entire SSH setup that had been configured and tested successfully but never saved — a genuinely costly lesson about the difference between running-config and startup-config.

```bash
show startup-config | section ip ssh pubkey-chain
```
**What it does:** Verifies the change actually persisted to the *saved* config, not just the currently-running one — the right way to confirm a save actually worked, rather than assuming.

### SSH client compatibility flags for old Cisco IOS

```bash
ssh -i /root/.ssh/cherwood_backup_rsa \
    -oKexAlgorithms=+diffie-hellman-group14-sha1 \
    -c aes256-cbc \
    -oHostKeyAlgorithms=+ssh-rsa \
    -oPubkeyAcceptedKeyTypes=+ssh-rsa \
    -oStrictHostKeyChecking=no \
    admin@10.10.99.2
```
**What each flag does, and why each was needed** (discovered one at a time, each error revealing the next layer):
- `-i` — specifies which private key to use for authentication
- `-oKexAlgorithms=+diffie-hellman-group14-sha1` — modern SSH clients deprecated older key-exchange algorithms by default; this re-adds one the old IOS SSH server still offers, without removing any modern ones (`+` appends rather than replaces)
- `-c aes256-cbc` — explicitly selects a cipher the old IOS server supports; modern OpenSSH's default cipher list doesn't include older CBC-mode ciphers
- `-oHostKeyAlgorithms=+ssh-rsa` and `-oPubkeyAcceptedKeyTypes=+ssh-rsa` — modern OpenSSH deprecated plain `ssh-rsa` (as opposed to newer `rsa-sha2-*` variants) as both a host-key type and a pubkey-auth type; these flags re-enable it specifically for this connection
- `-oStrictHostKeyChecking=no` — skips the interactive "are you sure you want to connect" prompt, necessary for a script running unattended (a real tradeoff: this also disables protection against a genuine man-in-the-middle attack on that specific connection — acceptable here since it's a fixed, known internal IP on a trusted LAN segment, not something acceptable for an internet-facing connection)

**Why this matters beyond this project:** connecting modern tooling to older, still-common enterprise network gear is an extremely realistic scenario. The right response isn't to weaken your client's defaults globally — it's to scope a narrow, explicit exception to the one connection that genuinely needs it.

### The stale host-key problem

```bash
ssh-keygen -f "/root/.ssh/known_hosts" -R "10.10.99.2"
```
**What it does:** Removes a specific host's cached identity from the local `known_hosts` file. **Why this was needed:** after regenerating the 1921's SSH host key (as part of redoing the SSH setup from scratch), SSH correctly detected that the router's identity had changed from what was previously cached — and, appropriately, refused to connect, warning of a possible man-in-the-middle attack. Since the change was legitimate (intentional reconfiguration, not an attack), the fix is to explicitly clear the one stale entry — **not** to globally disable host-key verification, which would remove a real security protection for all future connections.

### FortiGate: SSH key setup (different mechanism)

```bash
config system admin
    edit admin
        set ssh-public-key1 "ssh-rsa AAAA... root@cherwood-monitoring"
    next
end
```
**What it does:** Unlike Cisco's separate `pubkey-chain` structure, FortiGate attaches an SSH public key directly to an admin account's own configuration. Notably, FortiGate accepts the **full standard `.pub` format in one line** (prefix, base64, comment all together) with no chunking needed — its CLI console handles long lines without the paste-corruption issues Cisco's console had.

### The backup script pattern

```bash
#!/bin/bash

DEVICE_NAME="1921"
DEVICE_IP="10.10.99.2"
BACKUP_DIR="/root/config-backups/${DEVICE_NAME}"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
NEW_BACKUP="${BACKUP_DIR}/${DEVICE_NAME}-${TIMESTAMP}.txt"
LATEST_LINK="${BACKUP_DIR}/latest.txt"
LOG_FILE="/root/config-backups/backup.log"

mkdir -p "$BACKUP_DIR"

ssh -i /root/.ssh/cherwood_backup_rsa [...compatibility flags...] \
    admin@${DEVICE_IP} "show running-config" > "$NEW_BACKUP" 2>/dev/null

if [ ! -s "$NEW_BACKUP" ]; then
    echo "$(date): FAILED - backup for ${DEVICE_NAME} was empty" >> "$LOG_FILE"
    rm -f "$NEW_BACKUP"
    exit 1
fi

if [ -f "$LATEST_LINK" ]; then
    if diff -q "$LATEST_LINK" "$NEW_BACKUP" > /dev/null; then
        echo "$(date): ${DEVICE_NAME} - no changes detected" >> "$LOG_FILE"
    else
        echo "$(date): ${DEVICE_NAME} - CONFIG CHANGED, diff below:" >> "$LOG_FILE"
        diff "$LATEST_LINK" "$NEW_BACKUP" >> "$LOG_FILE"
    fi
else
    echo "$(date): ${DEVICE_NAME} - first backup taken" >> "$LOG_FILE"
fi

cp "$NEW_BACKUP" "$LATEST_LINK"
```
**What each part does:**
- Pulls the device's config over SSH and saves it with a timestamp — a full snapshot, not a diff, each time it runs
- `[ ! -s "$NEW_BACKUP" ]` — checks if the file is empty (`-s` tests "file exists and has size greater than zero"); if the SSH pull failed silently, this catches it rather than saving/trusting a broken backup
- Compares the new snapshot against `latest.txt` (a pointer to the most recent good backup) using `diff` — if different, logs exactly what changed; if identical, just notes "no changes"
- Updates `latest.txt` to point at the newest snapshot at the end

**This gives you two things at once:** a full version history (every timestamped snapshot kept) and an at-a-glance change log (the diff-based summary), without needing a separate version control system.

**Real bug — pagination on the FortiGate:** the first FortiGate backup attempt returned only 217 lines (silently truncated mid-statement) instead of the expected several-thousand-line full config. Root cause: FortiGate's CLI has its own output pager (`--More--`), which an interactive session handles by waiting for a keypress — but a non-interactive SSH exec session has no way to send that keypress, so the connection just closed once the pager blocked further output. Fixed by disabling the pager first, in the same SSH session:

```bash
ssh -i /root/.ssh/cherwood_backup_rsa -oStrictHostKeyChecking=no \
    admin@${DEVICE_IP} << 'FGCMDS' > "$NEW_BACKUP" 2>/dev/null
config system console
set output standard
end
show full-configuration
FGCMDS
```
**What the heredoc (`<< 'FGCMDS' ... FGCMDS`) does:** sends multiple commands to the remote device in one SSH session, as if they were typed in sequence — first disabling the pager (`set output standard`), then running the actual config pull. The quoted `'FGCMDS'` delimiter prevents the local shell from trying to expand any variables inside the heredoc, treating it as literal text to send.

### Cron scheduling

```bash
crontab -e
```
Then:
```
0 2 * * * /root/backup-1921.sh
5 2 * * * /root/backup-switch.sh
10 2 * * * /root/backup-fortigate.sh
15 2 * * * /root/isolation-check.sh
```
**What the schedule format means:** `minute hour day-of-month month day-of-week command`. `0 2 * * *` means "at minute 0 of hour 2 (2:00 AM), every day, every month, every day of week" — i.e., run once daily at 2:00 AM. The four jobs are staggered by 5 minutes each so they don't all hit the network simultaneously, and the isolation check runs last, after all three backups have completed.

### The isolation-check script

```bash
check_policy_deny() {
    POLICY_NAME=$1
    BLOCK=$(awk -v RS="next\n" "/set name \"${POLICY_NAME}\"/{print}" "$CONFIG_FILE")

    if [ -z "$BLOCK" ]; then
        echo "ALERT: ${POLICY_NAME} is MISSING"
    elif echo "$BLOCK" | grep -q "set status disable"; then
        echo "ALERT: ${POLICY_NAME} is DISABLED"
    elif echo "$BLOCK" | grep -q "set action deny"; then
        echo "OK: ${POLICY_NAME} is present, enabled, and set to DENY"
    else
        echo "ALERT: ${POLICY_NAME} is present but NOT set to DENY"
    fi
}
```
**What this does, and the two real bugs found while building it:**

The function's job is to check whether a specific named firewall policy still exists, is still enabled, and is still set to deny traffic — this is **configuration drift detection**: catching the case where someone (including future-you) accidentally weakens a security-critical policy without noticing.

**`awk -v RS="next\n" "/pattern/{print}"`** — this line deserves explanation on its own. `RS` (Record Separator) is normally a newline in awk, meaning each line is treated as a separate "record." Here it's set to `"next\n"` instead — FortiGate's config format closes every policy block with a line containing just `next`, so this makes awk treat **entire policy blocks** as single records, rather than individual lines. The pattern then searches for which whole block contains the target policy's name, and prints that entire block. This is the key fix that made the check actually reliable.

**First bug:** an earlier version searched only *forward* from the `set name` line for `set action deny`, using `grep -A N` or a similarly-scoped awk pattern. This worked in casual testing, but failed silently on a real test case: **`set status disable`** — the field that actually indicates whether a policy is active — is written *before* `set name` in FortiGate's config output, not after. A forward-only search structurally could never see it, so a disabled policy was incorrectly reported as fine.

**How the bug was actually caught:** by *deliberately disabling a real policy* on the FortiGate and confirming the script correctly flagged it — not by reading the code and assuming it was correct. The first re-test attempts gave confusing "still OK" results, which turned out to be because the GUI toggle hadn't actually been saved yet; this was resolved by checking the live FortiGate state directly (`show firewall policy 3`) as an independent source of truth before continuing to debug the script's logic.

**Why this matters:** a check that has never been proven to actually detect a failure is not a trustworthy check. This script wasn't considered "done" until it was shown to correctly catch a real, deliberately-introduced fault, and correctly clear once that fault was fixed.

---

<a name="part-17"></a>
## Part 17 — Simulated Attack & Detection

### Port probing without external tools

```bash
for port in 22 23 80 443 3389 8080 21 25 53 445; do
  timeout 1 bash -c "echo > /dev/tcp/10.10.10.1/$port" 2>/dev/null \
    && echo "Port $port: OPEN" || echo "Port $port: closed/filtered"
done
```
**What it does:** `/dev/tcp/HOST/PORT` is a Bash-specific pseudo-device — writing to it attempts to open a TCP connection to that host/port, without needing any external tool like `nmap`. `timeout 1` caps each attempt at 1 second so a filtered/blackholed port doesn't hang the loop. This was used after `apt install nmap` failed due to an unrelated Debian mirror outage — a good example of substituting a zero-dependency approach when an external blocker has nothing to do with the actual goal.

### Live packet capture on the FortiGate

```bash
diagnose sniffer packet any 'host 10.10.40.2 and host 10.10.10.1' 4 20
```
**What each part means:**
- `diagnose sniffer packet` — FortiGate's built-in packet capture tool, similar in concept to `tcpdump`
- `any` — capture on all interfaces, not just one specific one
- `'host 10.10.40.2 and host 10.10.10.1'` — a BPF-style filter expression, capturing only traffic between these two specific hosts
- `4` — verbosity level (4 shows IP headers and payload summary)
- `20` — capture up to 20 packets, then stop automatically

**Why this was used:** standard log views (Forward Traffic, Local Traffic, Security Events) showed *nothing* for the blocked reconnaissance attempt, despite violation logging being confirmed enabled. Rather than concluding "nothing happened" from an absence of log entries (a dangerous assumption), a live packet capture was used to directly observe ground truth at the wire level. This revealed that packets **were** arriving at the firewall (`VLAN40_DMZ in ... icmp: echo request`) but **no reply was ever sent** — proving the traffic was being actively received and silently denied, just in a category ("local-in" traffic addressed to the firewall's own interface) that FortiOS doesn't surface in the standard GUI log views the way policy-based denials of *forwarded* traffic are.

---

<a name="part-18"></a>
## Part 18 — Guest Bandwidth Limiting

### FortiGate: Traffic Shaping Policy

**GUI-configured object, verified via CLI:**
```bash
show firewall shaping-policy
```
Output:
```
config firewall shaping-policy
    edit 1
        set name "Guest_Bandwidth_Cap"
        set service "ALL"
        set srcintf "VLAN20_Guest"
        set dstintf "wan1"
        set traffic-shaper "Guest_10Mbps_Cap"
        set srcaddr "all"
        set dstaddr "all"
    next
end
```

**The associated shared shaper:**
- Traffic priority: **Low** (Guest traffic is deprioritized relative to other VLANs under contention)
- Maximum bandwidth: **10,000 Kbps** (10 Mbps), applied as a **shared** cap across all Guest devices combined, not per-device

**Concept — "shared" vs. "per-IP" shapers:** a shared shaper enforces one total bandwidth ceiling across all matching traffic combined (all Guest devices share one 10 Mbps pool). A per-IP shaper would instead give each individual device its own separate cap. Shared is the standard choice for a guest network — the goal is protecting the rest of the network from being saturated by Guest traffic in aggregate, not limiting any one guest device specifically.

---

## General patterns worth remembering across this whole project

1. **A route existing does not mean traffic is permitted.** This showed up independently in SSL-VPN, Branch routing, and SNMP monitoring — routing tables and firewall policy are two separate layers, and both need to be correct.
2. **Interface-level Administrative Access is a separate permission gate from firewall policy**, on both PING and SNMP, more than once in this project. Always check both layers when troubleshooting "why can't X reach Y."
3. **Verify saved/persisted state, not just currently-running state**, whether that's `show startup-config` vs `show running-config` on Cisco, or checking a file's actual contents after a script writes it. A change that "works right now" isn't the same as a change that survives a reboot or a reload.
4. **When a config summary hides a field, check the full configuration.** Abbreviated views (`show X` vs `show full-configuration X` on FortiGate) can hide the actual source of a conflict.
5. **A check or test that's never been proven to fail is not a trustworthy check.** The isolation-check script and the packet-capture evidence in Part 17 both reflect this — validate detection logic against a real, deliberately-introduced fault before trusting it.
