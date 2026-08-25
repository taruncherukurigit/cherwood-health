# Interview Prep — Cherwood Health

A talk-track for discussing this project out loud. Organized as questions an interviewer might actually ask, with answers structured the way you'd want to say them — concise first, detail available if they want to go deeper.

**How to use this:** don't memorize these word-for-word. Read through it enough times that the *shape* of each answer is familiar, then say it in your own words. Interviewers can tell the difference between recited and understood.

---

## "Walk me through this project."

**30-second version:** "I built a segmented enterprise network for a fictional healthcare organization, on real Fortinet and Cisco hardware — not simulated. Four VLANs separating staff, guest, servers, and a public-facing DMZ, a routed branch office connected over RIP, SSL-VPN remote access, and then I layered on monitoring with Prometheus and Grafana, automated config backups with drift detection, and actually tested the segmentation with a real reconnaissance attempt from the DMZ that I confirmed got blocked using a packet capture."

**If they want more:** pick whichever thread is most relevant to the role — heavy on routing/switching for a network engineer role, heavy on the detection/monitoring/attack-simulation pieces for a security analyst role.

---

## "What was the hardest problem you ran into?"

Have two or three ready, not just one — pick based on what the interviewer seems to care about.

**For a "networking depth" answer:** the SSL-VPN troubleshooting in Part 11. "I had five separate, stacked problems producing the same generic error message. A cipher self-conflict where the firewall had banned the exact hash algorithms its own required cipher suite needed — that one I only found by comparing the abbreviated config view against the full configuration dump, since the abbreviated view was hiding the conflicting field entirely. Then a port-forward that looked saved in the router UI but wasn't. Then a missing firewall policy — enabling SSL-VPN doesn't automatically permit the traffic through the firewall, those are two separate layers. And underneath all of that, the actual dominant cause turned out to be Tailscale running on my test phone, conflicting with the VPN client's own tunnel interface. I only found that by stepping back and questioning the client side instead of continuing to assume the server config was still wrong."

**For a "systematic debugging" answer:** the isolation-check script in Part 15/16. "I wrote a script to verify my key firewall DENY policies stayed intact over time — config drift detection. It passed every test I threw at it. But I didn't trust that, so I deliberately disabled one of the real policies on the firewall and re-ran the check to see if it would actually catch it. It didn't — it said everything was fine. That told me my script had a real bug, not just a hypothetical one. Turned out I was searching forward from the wrong anchor point in the config text; the field that actually mattered was written *before* the field I was searching from. I fixed it, disabled the policy again, and confirmed the fix actually worked this time before trusting it."

**For a "low-level/hands-on" answer:** the Part 17 packet capture. "I ran a real port scan and ping test from my DMZ segment against my internal Trusted VLAN, expecting to see it blocked in the firewall's traffic logs. Nothing showed up — not even a deny entry, in any log category. Instead of concluding nothing happened, I used FortiGate's built-in packet sniffer directly on the CLI and watched the actual packets. They were arriving at the firewall — it just wasn't logging that specific category of denial anywhere in the GUI. That taught me the difference between traffic being forwarded through a firewall and denied, versus traffic addressed directly to the firewall's own interface and denied — they're logged completely differently."

---

## "Why did you build this instead of just doing CCNA labs?"

"CCNA labs teach the individual commands, but they don't teach you what happens when three of those commands interact in a way no lab exercise anticipated — like a router's SSH stack being too old for a modern SSH client's default settings, or a firewall silently dropping traffic in a way that doesn't show up where you'd expect it to. I wanted a project where the bugs were real, not scripted, so I'd actually build the debugging instinct, not just the command syntax. I'm still doing CCNA study in parallel — this project reinforces it, doesn't replace it."

---

## "Tell me about a time you had to make a tradeoff decision."

**The Branch AP hardware substitution.** "The access point I'd planned for my branch office turned out, when I actually powered it up and read the boot log, to be running the wrong firmware entirely — Lightweight instead of Autonomous — and its login credentials from a previous owner weren't recoverable in the time I had. I had two choices: sink more time into password recovery and a firmware conversion with no guaranteed outcome, or substitute a consumer access point I already had working elsewhere in the project. I went with the substitution, but I documented the real cost of that choice — it introduces a double-NAT hop that a 'clean' design wouldn't have — instead of hiding it. I think being upfront about a tradeoff like that is more valuable to show an employer than pretending everything went according to the original plan."

---

## "How do you approach troubleshooting something you've never seen before?"

"I try to isolate the layer before I isolate the specific cause. On this project, almost every hard bug came down to figuring out *which* layer was actually the problem — was it physical connectivity, interface-level permissions, routing, or firewall policy? Those look similar from the outside — 'this device can't reach that device' — but the fix is completely different depending on which layer is actually broken. I got good at checking them in order rather than guessing: is the link even up, is administrative access enabled on the interface, does a route exist, does a firewall policy actually permit it. That checklist approach caught the same class of bug — an interface-level permission gate — at least four separate times across this project, on completely different services (PING twice, SNMP twice)."

---

## "What would you do differently if you started over?"

Be honest here — a canned "nothing, it was perfect" answer reads poorly.

"A couple of things. First, I'd separate my general Servers VLAN from a dedicated Management VLAN from the start — right now my monitoring container sits on the same segment as general-purpose service containers, and it has a firewall exception to reach the network gear for monitoring. That's a reasonable simplification for a lab, but in a real deployment I'd want that separated so a compromised general-purpose container doesn't inherit reach into the management plane. Second, I'd save my configs to NVRAM immediately after every change instead of batching it — I actually lost a full SSH configuration on one of my routers once because I tested it, confirmed it worked, and moved on without saving, and a reload wiped it. Cheap mistake, expensive to redo."

---

## "Explain [specific technical concept] to me."

A few of these are worth having crisp, one-breath explanations ready for:

**"What's the difference between a route and a firewall policy?"**
"A route is the firewall or router's map of how to *physically reach* a destination — which interface to send a packet out of. A firewall policy is a separate decision about whether that traffic is *allowed* to make that trip at all. You can have a perfectly correct route to somewhere and still have every packet dropped, because the policy layer says no. I hit that exact gap three separate times on this project, in three different contexts — it's genuinely one of the most common real troubleshooting traps."

**"What is RIP, and why not something more modern like OSPF?"**
"RIP's a distance-vector routing protocol — routers share their full list of known networks with directly-connected neighbors periodically, and pick the path with the fewest hops. It's old, and it doesn't scale well to large networks, which is why OSPF or EIGRP are more common in real production environments. I used it here because the topology was small — one HQ site, one branch, a single link between them — and RIP's simplicity meant I could focus the learning on the actual concept of dynamic routing over a WAN link, rather than the added complexity of OSPF's area design. I know OSPF conceptually from CCNA study and could speak to when I'd reach for it instead."

**"What's SNMP, and what are its weaknesses?"**
"SNMP is a protocol for querying and managing network devices — a network monitoring system asks a device 'what's your interface throughput' and it answers, using something called a community string as authentication. The weakness, especially with SNMPv1/v2c like I used here, is that the community string is basically a shared plaintext password — no encryption, no per-user accounting. SNMPv3 fixes that with real authentication and encryption. I used v2c here because it's what my hardware supports cleanly and it's scoped to a single, specific monitoring host with a firewall rule restricting who can even reach it — but I'd reach for v3 in a real production deployment."

**"What's a DMZ, and why not just put a public site directly online?"**
"DMZ stands for demilitarized zone — a network segment that's expected to be internet-facing, but deliberately walled off from everything else internal. The idea is that if that one segment gets compromised, the attacker doesn't automatically get a foothold into your internal network too — they're contained to whatever's in that DMZ. In my case, I went a step further and didn't even open an inbound port for it — I used Cloudflare Tunnel, so the container makes an outbound-only connection to Cloudflare, and there's genuinely nothing listening for an internet scanner to find directly."

---

## Questions to ask them back

Interviews go better as a two-way conversation. A few genuine, relevant ones for a network engineer / security analyst context:

- "What does your team's config management and drift-detection setup look like today — is it something like what I built here, or a different tool entirely?"
- "How does your team typically handle vendor SSH/legacy-compatibility issues on older network hardware — is that something you still run into regularly?"
- "What does your on-call or incident-response process look like when something like a firewall policy gets accidentally disabled or misconfigured?"

---

## If they ask something you genuinely don't know

Don't bluff. "I haven't worked with that specifically, but based on [related thing you did know], here's how I'd approach figuring it out" is a much stronger answer than guessing confidently and being wrong. This project gives you a lot of real, demonstrated troubleshooting *process* to fall back on even for things you haven't directly touched.
