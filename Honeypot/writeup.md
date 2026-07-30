# Home Network Honeypot & Threat Detection Lab

**Status:** In progress — logging live attacker traffic, findings section will be expanded as more interesting activity is captured.

---

## Overview

A self-hosted honeypot environment deployed on a dedicated host on my home network, designed to attract and log real-world internet scanning and exploitation attempts without putting any production system at risk. The goal was twofold: build hands-on experience with detection engineering (log analysis, protocol decoding, IOC identification) and get practical experience designing a properly isolated network segment on consumer-grade gear.

**Stack:** T-Pot (Cowrie, Dionaea, Honeytrap, Sentrypeer, Suricata, and other honeypot daemons bundled with T-Pot) running on Debian, with the full ELK stack (Elasticsearch, Logstash, Kibana) for indexing and dashboarding captured events. Docker-based, all honeypot services run as isolated containers.

**Network:** TP-Link Omada ER605 router providing VLAN segmentation and DHCP reservations.

---

## Architecture & Network Segmentation

The honeypot sits on its own VLAN, isolated from the rest of the home network:

- **One-way isolation** — the management VLAN can reach into the honeypot VLAN for administration (SSH, Kibana), but the honeypot VLAN cannot initiate any connection back into production/management VLANs. This means that even if a honeypot container or the host itself were fully compromised, an attacker pivoting from it hits a dead end rather than reaching other devices on the network.
- Implemented entirely via stateful access-control rules and VLAN configuration on the Omada ER605 router.
- Isolation was independently validated before exposing any service to the internet — cross-VLAN connectivity probes from the honeypot segment confirmed no path back to production, and host-firewall rules were checked for correctness.

---

## Setup Notes

- T-Pot deployment on Debian, all sensors running as Docker containers (`docker network ls` shows a separate bridge network per honeypot type — Cowrie, Dionaea, Honeytrap, Sentrypeer, ipphoney, mailoney, redishoneypot, tanner, wordpot, etc.)
- Exposed only the intended honeypot ports to the internet via port forwarding on the router; management interfaces (SSH, Kibana web UI) are restricted to internal/management VLAN access only.
- Kibana used for the primary dashboarding/visualization of captured events; raw JSON logs are also available per-honeypot under each container's log directory for manual inspection without the web UI, e.g.:
  ```bash
  tail -f ~/tpotce/data/cowrie/log/cowrie.json | jq .
  tail -f ~/tpotce/data/honeytrap/log/attackers.json | jq .
  tail -f ~/tpotce/data/sentrypeer/log/sentrypeer.json | jq .
  ```

---

## Analysis Techniques

A few recurring techniques used when digging into captured events:

- **Decoding raw hex payloads** (Honeytrap's `attack_connection.payload.data_hex` field) using CyberChef's "From Hex" operation to recover plaintext for protocol probes like raw HTTP requests.
- **Recognizing binary protocol structures** that won't decode to readable text — e.g. TLS ClientHello handshakes, which are structured binary (record header, client random, cipher suite list, extensions) rather than plaintext. The cipher suite ordering and extension list can be used to compute a JA3 fingerprint, which helps identify the scanning tool/client behind a connection independent of source IP.
- **SIP scanner identification** via Sentrypeer's `sip_message` field (stored as plain text) — checking the `User-Agent` header for known scanner signatures (e.g. `friendly-scanner` / SIPVicious).
- Cross-referencing source IPs against WHOIS/hosting-provider data to distinguish opportunistic mass-scanning infrastructure from more targeted activity.

---

## IOC Enrichment Workflow

To enrich source IPs captured by the honeypot with reputation, ownership, and infrastructure data, [SpiderFoot](https://www.spiderfoot.net/) runs on a **separate host from the honeypot** (my main machine, via WSL), not as part of the T-Pot stack itself — this keeps outbound OSINT lookups off a box that's intentionally internet-exposed, and avoids resource contention with the ELK stack.

**Setup (WSL, native Python — avoids Windows-specific dependency issues since SpiderFoot is developed primarily for Linux):**
```bash
sudo apt update && sudo apt install -y python3 python3-pip python3-venv git
git clone https://github.com/smicallef/spiderfoot.git
cd spiderfoot
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python3 sf.py -l 127.0.0.1:5001
```
Web UI at `http://127.0.0.1:5001` (WSL2 forwards `localhost` automatically, so it's reachable from a normal Windows browser).

Running it as a foreground process meant it died every time the WSL terminal closed. Converted it to a systemd service (WSL distro already has `systemd=true` set in `/etc/wsl.conf`) so it persists and auto-restarts:
```ini
# /etc/systemd/system/spiderfoot.service
[Unit]
Description=SpiderFoot OSINT Scanner
After=network.target

[Service]
Type=simple
User=bobby
WorkingDirectory=/home/bobby/spiderfoot
ExecStart=/home/bobby/spiderfoot/venv/bin/python3 sf.py -l 127.0.0.1:5001
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now spiderfoot
```

**Workflow:**
1. Pull a source IP from the T-Pot Attack Map's Live Feed or Kibana Discover.
2. In SpiderFoot, run an **"Investigate"** preset scan against that IP (tuned for threat-intel lookups — reputation, blacklists, malware associations — rather than broad recon).
3. Relevant modules: `sfp_abusech`, `sfp_spamhaus`, `sfp_alienvault` (blacklist/reputation feeds), `sfp_shodan` (open ports/banners, needs free API key), `sfp_ipinfo` / `sfp_whois` (geolocation/ownership).
4. Free API keys for Shodan, AbuseIPDB, and VirusTotal significantly widen module coverage — several of the more useful reputation modules are disabled or rate-limited without one.
5. Results feed directly into the Findings table below (IOC / Notes column).

---

## SIEM Integration (Wazuh)

While Kibana/ELK (bundled with T-Pot) already provides log aggregation and dashboarding, [Wazuh](https://wazuh.com/) was added as a purpose-built SIEM layer — correlation rules, MITRE ATT&CK mapping per alert, and host-level monitoring (file integrity, rootcheck, security configuration assessment) that ELK alone doesn't provide out of the box.

**Placement:** like SpiderFoot, the Wazuh manager/indexer/dashboard stack runs on a separate host from the honeypot (main PC, via WSL2 + Docker), not on the T-Pot box itself — keeping the SIEM off the internet-exposed host and avoiding resource contention with the existing ELK stack.

**Setup:**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
git clone https://github.com/wazuh/wazuh-docker.git -b v4.9.2
cd wazuh-docker/single-node
sudo sysctl -w vm.max_map_count=262144
docker compose -f generate-indexer-certs.yml run --rm generator
docker compose up -d
```

**Connecting the honeypot agent across VLANs:** the honeypot's one-way network isolation (see Architecture section above) blocks it from reaching the management VLAN by default — which meant the agent couldn't register with the manager until a narrow, explicit exception was added:

- Defined a custom Service Type (`Wazuh-Agent`, TCP, destination ports 1514–1515) in the Omada router's Preferences → Service Type page.
- Added an `Allow_Honeypot_to_Wazuh` ACL rule (Source Network: Honeypot → Destination: management host, that specific service only), and set its rule ID so it evaluates *before* the existing `Block_Honeypot_to_LAN` deny rule (Omada ACLs are first-match, evaluated in ID order).
- Verified reachability at each layer independently (`nc -zv -n <ip> <port>` from the honeypot) before assuming the whole path worked — this caught a Windows Firewall block and a WSL2 mirrored-networking config gap that would have been hard to isolate otherwise (see Lessons Learned).

Once reachable, the agent was deployed from the dashboard's **Deploy new agent** wizard (DEB amd64 package, manager address `192.168.0.109`), confirmed via `/var/ossec/logs/ossec.log` showing `Connected to the server`.

**Ingesting T-Pot's own logs:** to get Cowrie/Honeytrap/Sentrypeer events flowing into Wazuh (not just host-level telemetry), added `<localfile>` blocks (`log_format: json`) to the agent's `ossec.conf` pointing at each T-Pot log file, and enabled `logall`/`logall_json` on the manager so raw events are indexed even without a matching built-in rule (none exist yet for T-Pot's log formats — they land in analysisd's generic "other" bucket, still fully visible in `wazuh-archives-*`). Also had to enable the `archives` fileset in the manager's Filebeat module config (`/etc/filebeat/filebeat.yml`, disabled by default — only `alerts` ships out of the box) so archived events actually reach the indexer at all.

**Verified end-to-end:** confirmed with a live test — SSH'd into the honeypot to trigger a fresh Cowrie session, then found the full event sequence (`cowrie.session.connect`, `cowrie.client.version`, `cowrie.client.kex`, `cowrie.login.success`, etc.) in Discover under `wazuh-archives-*`, correctly parsed field-by-field (`data.eventid`, `data.username`, `data.src_ip`, SSH client hassh fingerprint) by Wazuh's generic JSON decoder — despite there being no Cowrie-specific decoder built in.

**Custom rules for correlated alerts:** since no Cowrie-specific rules ship with Wazuh, wrote a local rule set (`/var/ossec/etc/rules/local_rules.xml`, IDs 100200–100206) matching on the fields Wazuh's generic JSON decoder already exposes (`eventid`, `username`, `src_ip`, `input`) rather than needing a custom decoder at all:

| Rule ID | Level | Fires on | Example alert |
|---|---|---|---|
| 100200 | 0 (silent) | any `cowrie.*` event | base rule, groups the rest via `if_sid` |
| 100201 | 5 | `cowrie.session.connect` | new connection opened |
| 100202 | 5 | `cowrie.login.failed` | routine failed login |
| 100203 | 10 | `cowrie.login.success` | attacker actually got into the fake shell |
| 100204 | 7 | `cowrie.command.input` | captures the literal command typed, e.g. "attacker executed command: exit" |
| 100205/100206 | 12 | file download/upload | potential real malware sample landing on the honeypot |

Verified working via a live SSH test: rules 100201, 100203, and 100204 all fired correctly, with `$(username)`, `$(src_ip)`, and `$(input)` interpolating into the alert description exactly as expected (e.g. *"Cowrie honeypot: ATTACKER LOGGED IN (user: test4) from 192.168.0.109"*).

**Extended to Sentrypeer** (rules 100210–100214, matching on `app_name`/`sip_method`/`sip_user_agent` — same flat-JSON approach as Cowrie, since Sentrypeer's log is also single-level) and **Honeytrap** (rules 100220–100224), verified with live SIP/HTTP test traffic against each.

**Honeytrap needed a different matching approach.** Its JSON is deeply nested (`attack_connection.payload.data_hex`, etc.), and while Wazuh's *indexer* flattens nested fields into dotted names for search (`data.attack_connection.remote_ip`, visible in Discover), the **rule engine itself does not support matching against those dotted/nested field paths** — `<field name="attack_connection.protocol">` silently never matched, even though the field clearly existed in the indexed output. The fix was matching against the raw `full_log` text directly with `<regex type="pcre2">` instead of `<field>`, which works regardless of JSON nesting depth.

**A regex syntax mistake crashed the entire rule engine.** An early version of the Honeytrap regex used character classes and alternation without `type="pcre2"` — Wazuh's default (non-PCRE2) rule regex syntax rejected it, and critically, this wasn't a "that one rule silently fails" problem: it caused `wazuh-analysisd` to fail loading the *entire* ruleset (`CRITICAL: Error loading the rules`), silently killing **all** alerting — including the previously-working Cowrie and Sentrypeer rules — until the syntax was fixed and the manager restarted. Lesson: after any rule change, explicitly grep `ossec.log` for `"Error loading the rules"` before assuming things still work, since a single bad rule can take down the whole ruleset without crashing the container itself.

| Rule ID | Honeypot | Level | Fires on |
|---|---|---|---|
| 100200 | Cowrie | 0 (silent) | any `cowrie.*` event — base rule for `if_sid` chaining |
| 100201 | Cowrie | 5 | new connection |
| 100202 | Cowrie | 5 | failed login |
| 100203 | Cowrie | 10 | successful login (attacker got into the fake shell) |
| 100204 | Cowrie | 7 | command executed — captures the literal command text |
| 100205/100206 | Cowrie | 12 | file download/upload — possible malware drop |
| 100210 | Sentrypeer | 0 (silent) | any Sentrypeer event |
| 100211 | Sentrypeer | 7 | known SIP scanner user-agent (e.g. SIPVicious) |
| 100212/100213 | Sentrypeer | 7 | SIP REGISTER/INVITE — possible toll fraud attempt |
| 100214 | Sentrypeer | 3 | SIP OPTIONS — routine probing |
| 100220 | Honeytrap | 0 (silent) | any Honeytrap event with a payload |
| 100221 | Honeytrap | 5 | connection with actual payload bytes (excludes bare port scans) |
| 100222 | Honeytrap | 7 | payload starts with TLS ClientHello (`1603` hex) |
| 100223 | Honeytrap | 7 | payload starts with plaintext HTTP GET (`47455420` hex) |
| 100224 | Honeytrap | 12 | `download_count` nonzero — actual malware sample captured |

**Next step:** these are single-event rules; a natural extension is frequency-based correlation (e.g. `<frequency>`/`<timeframe>` to flag the same source IP hitting multiple honeypots in a short window, or repeated failed logins), which Wazuh supports natively without any decoder/regex changes.

---

## Operational Hardening

**Router port-forwarding audit.** Before widening the forwarded range from `64298-65535` to `1-64293` + `64298-65535`, verified there was no other path into the honeypot that would bypass the intended exclusion of T-Pot's own admin ports (64294 Cockpit, 64295 SSH, 64297 web UI): checked One-to-One NAT (empty), NAT-DMZ (no host set), Port Triggering (empty), and UPnP (disabled, no portmap entries). Confirmed the only inbound paths are the two explicit Virtual Server rules.

**Noise filtering.** Once real attacker data started flowing, the operator's own testing traffic (repeated manual SSH/curl/nc tests) was polluting raw counts — one IP alone accounted for 61% of early Cowrie events. Two layers of filtering added:
- **T-Pot/Kibana:** saved Discover session "External Traffic Only (No Testing Noise)" — `not src_ip:192.168.0.0/16 and not src_ip:38.45.84.73` (KQL supports CIDR directly on IP-type fields without quotes).
- **Wazuh:** silencing rule (`local_rules.xml`, ID 100230) matching internal/own-IP traffic via `<regex type="pcre2">` against `src_ip`/`source_ip`/`remote_ip`, placed as a sibling child of the same `if_sid` base rules — Wazuh resolves multiple matching children of the same parent by taking the **last-defined match**, so placing this rule after the specific alert rules lets it override them (level 0 = no alert) without touching the original rules. Verified live: a test SSH session from the operator's own IP produced zero Wazuh alerts, while concurrent real external traffic passed through untouched.

**Archive retention.** `logall_json` (enabled earlier to capture unmatched events) writes every processed event to `wazuh-archives-*` indices with no built-in expiration — a real risk once the wider port range multiplies event volume. Created an OpenSearch ISM (Index State Management) policy (`wazuh-archives-retention`) via **Indexer management → Index Management → Create policy**, using an `ism_template` binding (`index_patterns: ["wazuh-archives-*"]`) so it auto-applies to current and future daily indices without a manual per-index attach step. Deletes indices after 30 days.

---

## Findings

**Methodology note:** initial analysis over-attributed activity to malicious actors before cross-referencing reputation sources. Corrected findings below reflect verification against Cisco Talos, rDNS, and ASN ownership rather than first impressions (see Lessons Learned). Also note: **92%+ of early Cowrie activity was the operator's own testing traffic** (`192.168.0.104`/`.109`) — always exclude known-internal/testing IPs before drawing conclusions from raw counts (a saved Kibana search, "External Traffic Only (No Testing Noise)," now filters this automatically).

| Date | Honeypot | Summary | IOC / Notes |
|---|---|---|---|
| 2026-07-27 | Honeytrap | Large sustained scan from a `/24` block (5+ IPs incl. `85.217.149.60`, `.18`, `.59`, `.19`, `.47`) hitting TLS and HTTP probes. **Corrected finding:** rDNS confirms `o0XX.scanner.modat.io` — this is **Modat B.V.**, a declared internet-wide research scanner (same category as Censys/Shodan). Talos: not on any blocklist, sender reputation "poor" only in the generic netblock-reputation sense scanner infrastructure always carries. Benign. | ASN 209334 (Modat B.V.), Beauharnois, Canada. Not malicious — informational only. |
| 2026-07-27 | Honeytrap | HTTP GET `/SDK/webLanguage` probe (Hikvision/Dahua IP-camera exploit path) from `35.203.210.51`/`.19`, and `35.237.138.101` doing bare telnet connects to Cowrie. **Corrected finding:** ASN 396982 "Google LLC" is GCP's customer-egress ASN, not Google itself — traffic is third-party scanners renting GCP. One payload self-identified via User-Agent as **Palo Alto Cortex Xpanse** (attack-surface management scanner). Benign, rented infra. | GCP us-east1 (North Charleston, SC rDNS). No login attempted, no commands executed. |
| 2026-07-27 | Honeytrap | 246 events from a 9-IP cluster (`195.182.16.23` primary, plus `5.61.209.44`, `80.82.64.25`, `89.248.171.23`, etc.) across Amarutu Technology Ltd (AS206264) and IP Volume inc (AS202425) — netblocks in the Ecatel/Quasi Networks lineage, historically bulletproof-hosting-adjacent. Includes the `/SDK/webLanguage` exploit probe and a `SURICATA HTTP Request excessive header repetition` anomaly signature. **This is the most credible malicious actor identified pre-port-expansion** — unlike Modat/Censys/Xpanse, this infrastructure doesn't self-declare and shows anomalous protocol behavior. | AS206264 / AS202425. No successful exploitation confirmed — probe/recon stage only. |
| 2026-07-27 | Cowrie | Sustained low-volume Discord TLS traffic (`discord.com` SNI, ~386 connections/24h, ~10 min interval) initially flagged as possible C2. **Resolved:** full outbound-SNI audit (947 connections, 30 days) shows only 6 total destinations — Discord (operator's own alerting webhook), `api.ipify.org` (T-Pot's own external-IP lookup), `epr.elastic.co`, `ghcr.io`, `download.docker.com`, `packages.wazuh.com`. Every outbound connection accounted for; no unexplained egress. | Not an incident. Strongest evidence the honeypot host itself is uncompromised. |
| 2026-07-27 | Cowrie | 40x `CVE-2024-6387` (regreSSHion) Suricata alerts initially flagged as inbound exploit attempts. **Resolved:** all 40 are `192.168.20.100 → {192.168.0.104, .109}` — the honeypot's own SSH banner answering the operator's legitimate admin logins, timestamps matching `last -n 20` exactly. Zero external exploit attempts against this CVE. Real host SSH (port 64295, never internet-exposed) was separately confirmed patched (`OpenSSH_10.0p2`). | False positive — direction misread on first pass. No action needed. |
| 2026-07-27 (pre-expansion) | Cowrie | Across all honeypot activity before the router's port range was widened: **zero successful external logins, zero commands executed by external actors, zero file uploads/downloads, empty username/password tag clouds.** Only one external IP (`35.237.138.101`) ever reached Cowrie at all, and it only opened/closed telnet sessions with no auth attempt. | Clean bill of health for the pre-expansion period — narrow port forwarding (`64298-65535` only) meant most opportunistic scanning never reached the honeypot's bait services. |
| 2026-07-28 | Multiple | Router port forwarding expanded to `1-64293` + `64298-65535` (excluding T-Pot's own admin ports 64294/64295/64297). Attack volume jumped from ~433 events/30 days to **323 events in the first 6 hours**, and honeypot diversity expanded from mostly Honeytrap/Cowrie to also include Heralding, Dionaea, ConPot, Ciscoasa, RDPHoneypot, Adbhoney, H0neytr4p. Confirms the wider range was suppressing most realistic attack surface. | N/A — infrastructure change, not an attack. |
| 2026-07-28 | Honeytrap (port 8080) | **`ET EXPLOIT Apache ActiveMQ Remote Code Execution Attempt (CVE-2023-46604)`** from `94.154.43.230` — a real unauthenticated RCE, the initial-access vector for several ransomware campaigns since late 2023. Single HTTP transaction, 714 bytes to server (consistent with the exploit's malicious XML payload, not a bare probe); Suricata's own HTTP parser flagged `app_layer_error` (malformed/non-browser request). Tagged `ip_rep: known attacker` and flowbits `[ET.Evil, ET.DshieldIP]` — two independent reputation sources agree. p0f detected an OS-fingerprint inconsistency (`os_diff ttl mtu`, "host change"), suggesting the connection may have passed through a proxy. **Most serious single event captured to date.** | `94.154.43.230`, AS219502 "Storm Industries LLC," Amsterdam NL. Recommend treating as a confirmed targeted exploit attempt in any writeup/resume bullet. |
| 2026-07-28 | Dionaea (port 5432, PostgreSQL) | Genuine automated credential-stuffing: two sequential IPs in the same /24 (`64.89.163.83`, `64.89.163.133`, ASN Netiface America, Inc.) each ran the identical sequence `postgres:postgres → postgres:123456 → postgres:password`, ~15 minutes apart. Textbook default-credential brute-force tooling. | `64.89.163.0/24`. First real credential-based attack captured (username/password tag clouds were empty before this). |
| 2026-07-28 | Multiple | `ET DROP Dshield Block Listed Source group 1` fired 136+ times post-expansion. **Note for future analysis:** this is diffuse across 15+ unrelated IPs/ASNs (Hurricane Electric, Vpsvault.host, Google, Censys, Driftnet Ltd) — DShield is a crowd-sourced blocklist reflecting "flagged as a scanner somewhere, at some point," not one persistent adversary. Treat as background noise volume, not an actor to profile. | Background signal only — do not conflate with the ActiveMQ/Postgres findings above. |
| 2026-07-28 | Cowrie (telnet, port 23) | **Confirmed malware infection — first real sample captured.** `91.92.40.18` logged in with `root:root` over telnet, Cowrie's emulated architecture presented as `linux-mips-lsb`, then ran the classic botnet writability pre-check (`echo WRITABLE >/tmp/.testfile 2>&1; ls -l /tmp/.testfile`) before downloading two files via shell redirection. **VirusTotal confirms one is real malware:** SHA-256 `b5147693ed4a8744...` — 367-byte shell script, 2/60 vendors flagging it, popular threat label **`trojan.mirai/prometei`** (Lionic: `Trojan.Script.Prometei.4!c`; Rising: `Backdoor.Mirai/Linux!9.7A09C`), already in VT's database from 22h prior (actively circulating, not unique to this honeypot). The second "download" (SHA-256 `0dc95fb4077cce0b...`) is a false lead — 9 bytes, 0/58 detections, tagged `text`: it's just Cowrie capturing the literal output (`WRITABLE\n`) of the attacker's own test command, not a payload. **The entire sequence repeated ~35 minutes later** (`duplicate: true` on the second run) — same bot re-hitting the honeypot, consistent with automated worm-style reinfection sweeps. | `91.92.40.18`, AS197170 (TechTies Inc.), Eygelshoven, NL. Malware family: Mirai/Prometei loader targeting MIPS IoT devices. Sample retained at `/home/cowrie/cowrie/dl/b5147693...` on the honeypot for further analysis if desired. |
| 2026-07-29 | Dionaea (port 445, SMB) | **DoublePulsar/EternalBlue-era exploit attempt, genuine not a signature glitch.** `81.10.54.140` opened a single ~4-minute TCP session pushing 5.7MB into the SMB stream, tripping `ET EXPLOIT [PTsecurity] DoublePulsar Backdoor installation communication` 2,925 times against the same flow. Payload decode shows a valid SMB2 header followed by a long repeating 4-byte filler block — the heap-grooming pattern real EternalBlue/DoublePulsar tooling uses before sending the actual backdoor-ping, not a parser artifact. Dionaea only emulates SMB, so no real code execution occurred, but the intent and tooling are genuine 2017-era exploit kit behavior still being run opportunistically in 2026. | `81.10.54.140`, AS8452 "IDDQD-AS," Cairo, Egypt. Single scan pass (1,349 total events/24h, nearly all in this one window) — not sustained targeting. |
| 2026-07-29 | Cowrie (telnet) | **Prometei/Mirai actor returned and is rotating source IPs within the same /24**, not operating from a single static address. Reinfection sweep repeated 5x between 01:00–01:09 UTC from `91.92.40.18` (each pair: real sample `b5147693...` + the harmless `WRITABLE` test-file false lead, matching the 7/28 finding exactly), then again at 06:41 (test file only, no full payload this pass). A related but distinct address in the same block, `91.92.42.10`, separately generated 3,821 events same-day. **Revises prior single-IP framing** — the watchlist/IOC should be the `91.92.40.0/23`-ish TechTies Inc. netblock (AS197170), not just `91.92.40.18`. | AS197170 (TechTies Inc.). 12 rule-level-12 "malware drop" alerts in 12h, all traced to this actor. |
| 2026-07-29 | Sentrypeer (SIP, port 5060) | **Toll-fraud SIP dialing is now the single largest traffic category on the honeypot**, not a one-off probe. Two distinct IONOS-hosted IPs ran high-volume automated INVITE floods against different target numbers: `217.160.58.58` (~12k events/12h, dialing `9001390237902850`-style numbers with incrementing digits) and `85.215.109.60` (12,914 events/12h — largest single source of the whole window — dialing a UK number `+441904911060` through multiple international-prefix variants: `+44`, `0044`, `002 44`). Both use a generic `User-agent: VOIP`, so neither trips the existing SIPVicious-signature rule (100211). | AS8560 IONOS SE, Germany (rented VPS infra, both IPs). Justifies adding a frequency-based rule for repeated same-source SIP INVITEs (see Detection Engineering below). |
| 2026-07-29 | Dionaea/Honeytrap (port 61616) | **Apache ActiveMQ RCE (CVE-2023-46604) escalated from a single probe into an active multi-source campaign sharing payload infrastructure.** Three exploitation attempts in 12h, from two structurally unrelated botnet netblocks, both staging second-stage payloads in the same `94.154.43.0/24`: `94.154.43.10` (AS219502 Storm Industries LLC — same ASN as the 7/28 finding's `94.154.43.230`) hit twice, self-hosting `http://94.154.43.10/ipmiv2.xml`; `91.92.40.4` (AS197170 TechTies Inc. — the Prometei-linked netblock) hit once, pointing at `http://94.154.43.203/bins/dashboard.xml`. Each payload is a genuine Jolokia/Spring `ClassPathXmlApplicationContext` injection instructing the broker to fetch and deserialize a remote Spring XML bean file — the real RCE mechanics, not a bare version-check probe. **Payload URLs saved to `pending-malware-analysis.md` for retrieval once a sandbox VM is ready** — not fetched from the honeypot or workstation. | AS219502 / AS197170. Shared `94.154.43.0/24` payload infrastructure across two unrelated source botnets suggests either one actor running multiple bot families or a shared/rented exploit-delivery service — worth noting as infrastructure-level correlation rather than three independent incidents. |
| 2026-07-29 | Generic HTTP (port 8000) | **CVE-2025-55182 — Next.js/React Server Components "React2Shell" RCE, single organized scan, technically the most current exploit caught to date** (publicly disclosed Dec 2025, signature updated Apr 2026 — everything else in this table is 2017–2023-era). `160.119.71.92` sent 19 requests in a 46-second burst, systematically probing 5 candidate Server Action paths (`/_next`, `/api`, `/_next/server`, `/app`, `/api/route`), each with a different spoofed User-Agent (iPhone Safari, Firefox, Edge, Android) from the same source IP — a scanner fingerprint, not organic traffic. Payload is a correctly-constructed prototype-pollution gadget chain (`"then":"$1:__proto__:then"` → `"get":"$1:constructor:constructor"`) that pollutes `Object.prototype` to reach `Function.prototype.constructor`, the standard route from prototype pollution to arbitrary code execution via the Flight protocol's thenable resolution. No real Next.js app was listening, so it landed on a generic responder — competently built exploit, unsuccessful only by circumstance. | `160.119.71.92`, AS49870 Alsycon B.V., Seychelles. Confirmed via Suricata sig `2066027` / CVE-2025-55182 metadata; worth cross-referencing against Talos/AbuseIPDB per the existing SpiderFoot workflow before the next writeup pass. |

---

## Detection Engineering — Watchlist & Frequency Rule (in progress, not yet live)

Attempted to extend `local_rules.xml` with two new rules in response to the 7/29 findings above:

- **CDB list watchlist** (`etc/lists/known-malicious-ips`, created and saved successfully via Indexer/Server management → CDB Lists) seeded with `91.92.40.18` → `mirai_prometei_repeat_offender`. Not yet activated pending a manager restart.
- **Rule 100240** (level 12): fires whenever a source IP in the CDB list hits any T-Pot base rule (`100200`/`100210`/`100220`), via `<list field="src_ip" lookup="match-key">`, to surface repeat offenders distinctly from first-time hits.
- **Rule 100241** (level 10, `frequency="10"` `timeframe="60"`): frequency-correlation on rule `100213` (Sentrypeer SIP INVITE) with `<same_source_ip>`, intended to catch the toll-fraud dialer pattern (`217.160.58.58`, `85.215.109.60`) as a single correlated alert instead of thousands of individual level-7 events.

**Status: blocked.** Every save attempt (both from the browser UI and independently) fails with the generic `Error: Could not upload rule (1113) - XML syntax error`, with no line/column detail surfaced by the UI. Ruled out so far: self-closing vs. explicit-closed `<same_source_ip>` tags (both fail identically), and editor auto-bracket-closing corruption (verified this specific rules editor does *not* auto-close tags, unlike the OpenSearch Dashboards JSON editor — see Lessons Learned). Next step is checking the manager's own `ossec.log` for the actual parser error (same technique used for the earlier Honeytrap regex crash), since the UI's wrapper error is uninformative. Both new rules are content-complete and ready to re-apply once the underlying syntax issue is identified.

---

## Lessons Learned

- **"Unreachable honeypot" turned out to be a VPN routing issue on the client side**, not the honeypot at all — an active VPN on the connecting machine was routing traffic off the LAN entirely, so pings never reached the local subnet. Good reminder to check the client's own network path before assuming a target host is down.

- **A device can't reliably test TCP connectivity to its own external LAN IP** ("NIC hairpinning") — many NIC drivers/switches silently drop a host's own traffic sent back to its own external address, regardless of firewall config. Wasted time chasing a Windows Firewall/WSL config issue that turned out to be this instead; the real test needs to originate from a genuinely separate device (in this case, the honeypot itself, which was the actual path that mattered anyway).

- **WSL2 "mirrored" networking mode has its own firewall quirks** — even with the shared host IP confirmed working and a matching Windows Firewall allow rule in place, traffic didn't get through until `.wslconfig`'s `[experimental]` section explicitly had `firewall=true` set, followed by a full `wsl --shutdown` (not just closing the terminal) to reload the networking config.

- **Scripts/venvs under `/mnt/c/...` (Windows-mounted DrvFs) can silently fail to execute under systemd** even though they run fine when invoked manually from an interactive shell — surfaced as a `203/EXEC` systemd error with no obvious cause. Fix was moving the project into WSL's native Linux filesystem (`~/`) rather than working around permissions on the Windows mount. General takeaway: keep working project files off `/mnt/c` in WSL, use it only for accessing native Windows files when actually needed.

- **Router ACLs are evaluated first-match, in ID order** — a new "allow" rule appended after an existing broad "deny" rule is silently unreachable. Any new exception to a deny-by-default policy needs its rule ID placed explicitly above the rule it's meant to carve an exception out of.

- **A file being readable by its owning group doesn't help if a parent directory blocks traversal** — the Wazuh agent's log collector could read T-Pot's honeypot log files fine (owned by the `tpot` group, which the `wazuh` user was added to), but nothing arrived at the manager until `/home/robert` itself (mode `700`) was found blocking all traversal into the path for any non-owner user. Diagnosing this required `namei -l` to walk the full permission chain — checking only the target file's own permissions wasn't enough.

- **Docker Compose bind-mounted config files can silently make in-container edits non-persistent.** Editing `ossec.conf` directly inside the running Wazuh manager container (`docker exec ... sed ...`) appeared to work, but reverted back to defaults on the next `docker restart` — because the container's entrypoint recopies its config from a host-side template file (`config/wazuh_cluster/wazuh_manager.conf`) on every startup. The fix was editing that host template directly rather than the live container's copy. General lesson: when a containerized app's config keeps "reverting," check `docker-compose.yml` for a bind mount before assuming the edit itself was wrong.

- **A rule engine's dynamic-field matcher may not support the same nested-field paths its own indexer exposes downstream.** Wazuh's generic JSON decoder flattens nested objects into dotted field names visible in Discover (`data.attack_connection.remote_ip`), but `<field name="attack_connection.protocol">` in a rule silently never matched — the rule engine evaluates fields before that flattening happens and doesn't support dotted nested paths the same way. Matching against the raw log text with `<regex type="pcre2">` instead of `<field>` fixed it. Don't assume a field visible in the search UI is necessarily matchable at the rule-evaluation stage.

- **A single malformed custom rule can silently take down the entire rule engine, not just itself.** A regex using character classes/alternation without Wazuh's required `type="pcre2"` attribute caused `wazuh-analysisd` to fail loading the *whole* ruleset (`CRITICAL: Error loading the rules`) — the container kept running (other daemons were unaffected), giving no obvious sign that alerting had silently stopped entirely, including previously-working rules unrelated to the bad one. After any rule change, explicitly grep the log for `"Error loading the rules"` rather than assuming a clean `docker restart` means the rules loaded.

- **A netblock or ASN showing up in reputation tools isn't itself evidence of malicious intent** — internet-wide research scanners (Modat, Censys, Shodan, Palo Alto Cortex Xpanse) generate exactly the same "high hit count / poor netblock reputation" signature as real attackers, because they're constantly scanning too. The distinguishing signal is **self-declaration** (rDNS like `*.scanner.modat.io`, User-Agent strings naming the tool) and **cross-referencing an actual reputation authority** (Talos, Spamhaus block lists) rather than reasoning from volume or SpiderFoot's netblock-level "blacklisted IP on owned netblock" metric, which conflates "shares a /24 with something bad, ever" with "is currently malicious." First-pass analysis in this project over-attributed several benign scanners as attackers before this check was applied — worth doing the reputation lookup *before* writing conclusions, not after.

- **Wazuh resolves multiple matching sibling rules by taking the last-defined match, not the highest level.** This is usable as a deliberate suppression mechanism: a low-priority/level-0 rule placed *after* existing alert rules in the same rule group, matching a narrower condition (e.g. internal source IP), overrides them without editing the original rules at all. Confirmed by testing — a rule 100230 added after rules 100200/100210/100220's children successfully silenced alerts for internal test traffic while leaving external traffic unaffected.

- **Browser-based code editors (Ace/CodeMirror, used in OpenSearch Dashboards) can silently corrupt multi-line pasted/typed input via auto-bracket-closing** — typing a JSON object across multiple lines caused duplicate closing braces to accumulate, since the editor auto-inserts a matching `}`/`]` immediately after each opening one, and a manually-typed closing character later doesn't "consume" the auto-inserted one once the cursor has moved away (e.g. to a new line). Typing the same content as a single line (no newlines) avoided the mismatch entirely, since the cursor stays immediately adjacent to the auto-closed character and typing over it merges cleanly. Also note: these editors often require pressing **Enter to enter edit mode** before any keyboard shortcut (including Ctrl+A) affects the actual buffer — clicking alone isn't sufficient.

- **Not every embedded code editor shares the same auto-close quirks** — the Wazuh Rules file editor (a different Ace instance from the OpenSearch Dashboards JSON editor above) does *not* auto-insert closing tags when typing XML; confirmed by deliberately typing an unclosed `<group>` tag and observing the validator flag it as unclosed rather than silently pairing it. Don't assume a lesson learned on one embedded editor generalizes to every other editor in the same product family — verify per editor.

- **The Wazuh Rules file editor's click target is the entire text buffer, not a separate search box** — after navigating back to the rules list and clicking a file to open it, a click at the same screen coordinates used for the *list's* search field lands inside the *editor's* text content instead, since the editor occupies that same region once open. This silently typed stray characters directly into the rule XML mid-session, which then had to be found and reverted via undo. Always screenshot to confirm which view (list vs. editor) is actually on screen before clicking a remembered coordinate.

- **A generic UI error ("Could not upload rule (1113) - XML syntax error" with a JS stack trace but no line/column) can persist across multiple structurally different fixes**, meaning the wrapper error isn't reliable for localizing the actual problem — same principle as the earlier "Error loading the rules" case, except this UI doesn't even name the offending line. The "Ruleset Test" button in the same editor is a red herring for this purpose: it validates sample *log lines* against the existing ruleset (decoder/rule matching), not the rule *file's* XML syntax, so feeding it rule XML just produces nonsense "no decoder matched" output. The manager's own `ossec.log` remains the authoritative source for this class of error.
