# Advanced DDoS Protections Setup

Cross-platform **defensive** hardening toolkit for **Linux**, **macOS**, and **Windows 10/11**.

It builds protection against the common attack taxonomies — Layer-7 floods
(`GET`, `POST`, `SLOW`, `BYPASS`, `CFB`, `CFBUAM`, `BOT`, `STOMP`, `XMLRPC`, `KILLER`,
`BOMB`, `APACHE`, `RHEX`, …), Layer-4 floods (`TCP`, `UDP`, `SYN`, `ICMP`, `VSE`,
`MINECRAFT`, `MCBOT`, `MCPE`, `FIVEM`, `TS3`, `CPS`, `CONNECTION`, …), and Layer-4
amplification (`DNS`, `NTP`, `MEM`/Memcached, `CLDAP`, `CHAR`/Chargen, `ARD`, `RDP`).

It also hardens services (nginx, Apache, MySQL, SSHd, RDP, Postfix, Dovecot, Exim,
MSSQL, IIS), installs and configures fail2ban / brute-force protection, scans for
rootkits and backdoors, disables historically-exploited services, optionally
removes Windows bloatware and telemetry — and the whole thing can roll back.

> **Defensive only.** This repo contains no attack code, no traffic generators,
> no method of producing any of the floods it protects against. Every change is
> reversible via the bundled uninstaller.

---

## One-liner quickstart

### Linux / macOS
```bash
curl -sSL https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/bootstrap.sh | sudo bash
```

### Windows 10 / 11 (elevated PowerShell)
```powershell
irm https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/bootstrap.ps1 | iex
```

### Uninstall (same place you ran the bootstrap)
```bash
curl -sSL https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/uninstall-remote.sh | sudo bash
```
```powershell
irm https://raw.githubusercontent.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup/main/uninstall-remote.ps1 | iex
```

The bootstrap clones into `/opt/ddos-protect` (Linux/Mac) or
`C:\ProgramData\ddos-protect-src` (Windows). Re-run anytime to upgrade.

---

## Manual install

```bash
git clone https://github.com/NekoSuneProjects/Advanced-DDOS-Protections-Setup.git
cd <REPO>
sudo ./install.sh          # Linux / macOS — gives a menu
```
```powershell
.\install.ps1               # Windows — gives a menu
```

The installer shows a menu:
```
1) Full install (all applicable modules)
2) Choose modules
3) Dry-run (print what would happen)
4) Uninstall / restore
5) Exit
```

---

## What gets installed (by module)

### Linux modules
| # | Module | What it does |
|---|--------|--------------|
| 01 | Firewall + rate-limit | iptables/nftables: per-IP SYN/ICMP/conn limits, drop invalid/XMAS/NULL, blackhole amplification source ports (19/53/123/389/1900/11211/27015 …) **only if you don't run them**. Reads whitelist from `/etc/ddos-protect/whitelist.txt`. |
| 02 | sysctl/TCP hardening | SYN cookies, RFC1337, rp_filter, kptr_restrict, source-route off, martian log, kernel ASLR |
| 03 | fail2ban + jails | SSHd, nginx (auth/limit-req/botsearch/noscript + custom `nginx-ddos` filter), Apache, MySQL, Postfix, Dovecot, Exim, **recidive** (repeat offenders get 1-week bans). Only enables jails for services that are actually installed. |
| 04 | SSHd hardening | PermitRootLogin no, MaxAuthTries 3, modern ciphers/KEX/MACs. Won't disable password auth if you have no key — protects against lockout. |
| 05 | nginx hardening | `limit_req` / `limit_conn` zones, slowloris timeouts, drop bot UAs, kill TRACE/TRACK/DEBUG, `server_tokens off`. **Skips** if nginx isn't installed. |
| 06 | Apache hardening | mod_evasive, ServerTokens Prod, TraceEnable Off, rewrite-rule UA blocklist |
| 07 | MySQL/MariaDB hardening | bind-address localhost, max_connect_errors, max_user_connections, skip-name-resolve |
| 08 | Email hardening | Postfix anti-relay/anti-spam, smtpd rate limits, TLS 1.2+ only, Dovecot connection/process caps. Skips per service. |
| 09 | Rootkit/backdoor scan | Installs + runs **rkhunter**, **chkrootkit**, **Lynis**, optional **ClamAV**. Read-only — flags get pushed to your notification channels. |
| 10 | System audit | Listening sockets, SUID, world-writable, cron, systemd timers, every user's `authorized_keys`, processes with deleted executables. Read-only. |
| 11 | Disable unsafe services | Telnet, rsh, rlogin, tftp, avahi, cups, rpcbind, snmpd, vsftpd — **asks before disabling** anything currently running. |
| 12 | Cloudflare | `ddos-cf` helper: `on` / `off` (Under Attack mode), `block`/`unblock`/`list`. Installs a `cloudflare-ddos` fail2ban action so bans propagate to your CF zone. |
| 13 | Notifications | Wires Discord webhook, Telegram bot, ntfy.sh, Slack, Gotify, generic webhook. Installs `ddos-notify` CLI and a fail2ban `ddos-notify` action. |
| 14 | Realtime monitor | systemd timer (60s): CPU%, mem%, RX/TX Mbps, established+SYN-recv TCP count. Pushes to your channels above thresholds. `ddos-status` shows the latest sample. |
| 15 | Game/voice servers | Detects Minecraft Java/Bedrock, FiveM, TeamSpeak3, Mumble, Source-engine, Valheim, DayZ — applies tight per-source rate-limits in the firewall. |

### macOS modules
| # | Module | What it does |
|---|--------|--------------|
| 01 | pf firewall | Anchor `ddos-protect`: rate-limited SSH/HTTP, brute-force overload table, amp-port blackhole, fragment drop |
| 02 | sysctl | `net.inet.tcp.blackhole=2`, ICMP off, source-route off — persisted via LaunchDaemon |
| 03 | fail2ban | Homebrew install, SSHd jail with `pf` banaction |
| 04 | SSHd | drop-in `/etc/ssh/sshd_config.d/99-ddos-hardening.conf` |
| 05 | Audit | Listening ports, LaunchAgents/Daemons, login items, recent ssh failures |
| 06 | Cloudflare | Same helper as Linux |
| 07 | Notifications | Same channels as Linux |
| 08 | Realtime monitor | LaunchDaemon (60s) — same telemetry, `ddos-status` CLI |
| 09 | Game/voice servers | Auto-loads `ddos-protect-games` pf anchor with rate-limits |

### Windows modules
| # | Module | What it does |
|---|--------|--------------|
| 01 | Firewall | Enables Windows Firewall on every profile, whitelist from `%ProgramData%\ddos-protect\whitelist.txt`, amp-port blackhole, blocks RDP from Internet (LAN only), auto-allows game ports if detected. All rules tagged `-Group "DDoS-Protect"` for easy removal. Helper: `ddos-allow.ps1 <ip>`. |
| 02 | TCP/IP hardening | Registry: SynAttackProtect, TcpMaxHalfOpen, EnableICMPRedirect=0, DisableIPSourceRouting=2, etc. + disables SMBv1. Previous values saved to `state.json` for rollback. |
| 03 | RDP lockout | Enforces NLA, sets account lockout (5/30/30), enables 4625 audit |
| 04 | MySQL/MariaDB | Edits `my.ini` if a MySQL/MariaDB service is present — bind-address, max_connect_errors, … |
| 05 | Debloat | Removes UWP bloatware (Candy Crush, Bing, Xbox, Skype, Spotify, …) — **reversible**, restore point taken, package list in `state.json` |
| 06 | Telemetry block | Disables `DiagTrack`, `dmwappushservice`, `WerSvc`, `RemoteRegistry`, applies policy keys, **firewall-blocks** Microsoft telemetry endpoints (no hosts-file edits) |
| 07 | Defender | Enables real-time/behavior/script/email/IOAV monitoring, Network Protection, ASR rules, signature update, optional quick scan |
| 08 | Audit | Suspicious services (binary outside `Program Files`/`System32`), non-Microsoft scheduled tasks, autorun keys, WMI event subscribers, last-hour failed logons |
| 09 | Disable unsafe services | RemoteRegistry, SSDPSRV, upnphost, Browser, Fax, lfsvc, SharedAccess, … — opt-in per service |
| 10 | Cloudflare | Same helper, `ddos-cf.ps1 on/off/block/unblock/list` |
| 11 | Notifications | Same channels as Linux + Scheduled Task that watches Security 4625 burst (15 failed logons / 1 min => alert) |
| 12 | Realtime monitor | Scheduled Task (60s) sampling CPU/Mem/Network/TCP-conn; thresholds in `%ProgramData%\ddos-protect\monitor.json`; `ddos-status.ps1` shows latest sample |

---

## Turn it on / off

A single command flips every component of the toolkit on or off — without
removing any configs. Reboot restores the install state (configs persist).
For permanent removal use the uninstaller.

### Linux / macOS
```bash
sudo ddos-protect on        # firewall + fail2ban + watcher: on
sudo ddos-protect off       # all off, configs untouched
sudo ddos-protect status    # show each component
sudo ddos-protect restart   # off then on
```

### Windows (elevated PowerShell or cmd.exe)
```powershell
ddos-protect on             # firewall rules enabled + scheduled tasks running
ddos-protect off            # everything disabled, configs untouched
ddos-protect status
ddos-protect restart
```

What gets toggled:
- **Firewall**: iptables `DDOS_PROTECT` chain hook / nftables `ddos_protect`
  table / pf state / Windows Firewall `DDoS-Protect` rule group
- **fail2ban** service (Linux + macOS)
- **Realtime watcher** (`ddos-watcher.timer` / launchd `com.ddosprotect.watcher`
  / Scheduled Task `DDoS-Protect Watcher`)
- **4625 alert task** (Windows)

Cloudflare "Under Attack" mode is a separate switch: `ddos-cf on` / `ddos-cf off`.

---

## Whitelist / allowlist

Add your management IP **before** you tighten the firewall. Otherwise rate-limits
and amp-port blocks can lock you out.

### Linux / macOS
```bash
sudo ddos-allow 203.0.113.5
sudo ddos-allow 192.168.0.0/16
```
Or edit `/etc/ddos-protect/whitelist.txt` and re-run module 01.

### Windows
```powershell
powershell -File "$env:ProgramData\ddos-protect\ddos-allow.ps1" 203.0.113.5
```

The whitelist file is **gitignored** so private addresses never reach GitHub.

---

## Notifications

Module 13 (Linux), 07 (macOS) or 11 (Windows) configures any of:

- **Discord** — webhook URL
- **Telegram** — bot token + chat ID
- **ntfy.sh** — topic (free, push to phone via app)
- **Slack** — webhook URL
- **Gotify** — URL + app token
- **Generic webhook** — plain JSON POST

All channels fire in parallel. Cooldown (`ALERT_COOLDOWN_SECONDS`, default 600s)
keeps you from getting spammed. The realtime monitor (modules 14 / 08 / 12) uses
them automatically; fail2ban gets an `ddos-notify` action you can append to any
jail's `action =` line.

Ad-hoc:
```bash
ddos-notify "manual test" "everything is fine" info
```

---

## Cloudflare integration

Module 12 (Linux), 06 (macOS), 10 (Windows) — store an API token (scoped to
`Zone:Zone:Edit` + `Zone:Firewall Services:Edit`) and use:

```bash
ddos-cf on              # enable Under Attack mode for the zone
ddos-cf off             # back to "medium"
ddos-cf block 1.2.3.4   # zone-level access rule
ddos-cf unblock 1.2.3.4
ddos-cf list
```

Also installs a `cloudflare-ddos` fail2ban action — add it to any jail's
`banaction =` to push every IP fail2ban bans straight to Cloudflare too.

---

## Uninstall / restore

### Linux & macOS
```bash
sudo ./uninstall.sh
```

### Windows
```powershell
.\uninstall.ps1
```

The uninstaller:
- Removes the `DDOS_PROTECT` / `DDoS-Protect` firewall chain and rules
- Stops fail2ban (Linux/Mac) and restores the previous `jail.local`
- Deletes our nginx/Apache/MySQL/SSHd/Postfix/Dovecot drop-ins and reloads each
  service
- Restores the original sysctl / TCP-IP registry values from `state.json`
- Re-registers every removed UWP package (Windows)
- Re-enables every service it disabled (Linux + Windows)
- Removes scheduled tasks / systemd timers it added
- Archives `state.json` as `state.json.uninstalled-<timestamp>` for forensics

---

## Repository layout

```
.
├── README.md
├── LICENSE
├── .gitignore                       # ignores logs, state, restore, whitelist
├── .gitattributes                   # LF for *.sh, CRLF for *.ps1
├── bootstrap.sh / bootstrap.ps1     # curl|sudo bash  ·  irm|iex
├── install.sh / install.command / install.ps1
├── uninstall.sh / uninstall.ps1
├── uninstall-remote.sh / uninstall-remote.ps1
├── lib/
│   ├── ui.sh         · ui.ps1       # banner, menu, log, yes/no, spinner
│   ├── detect.sh     · detect.ps1   # OS, distro, pkg-mgr, service detection
│   └── notify.sh     · notify.ps1   # 6-channel notification helper
├── linux/
│   ├── modules/   01-firewall .. 15-game-servers
│   └── configs/   sysctl, fail2ban (jail.local + filter), nginx drop-in
├── macos/
│   ├── modules/   01-pf .. 09-game-servers
│   └── configs/   pf anchor
└── windows/
    ├── modules/   01-firewall .. 12-monitor
    ├── configs/   bloatware-list, telemetry-services, telemetry-endpoints
    └── restore/   state.json snapshots (gitignored content)
```

---

## Safety notes

1. **Run on a snapshot/VM first.** Every action is reversible, but a misconfigured
   firewall on a remote host can lock you out. Modules that touch SSH/RDP warn first.
2. **Whitelist your management IP before module 01.**
3. **No host-level toolkit absorbs a multi-Gbps amplification flood.** For volumes
   above your link capacity, use an upstream scrubber (Cloudflare, OVH, Voxility,
   Path.net, etc.). This toolkit reduces what your host has to deal with after that.
4. **The Windows debloat is reversible**, but if you uninstall a UWP app it can
   take ~30s for the re-registration to settle on first re-launch.
5. **Modules that install software (`rkhunter`, `clamav`, `fail2ban`) ask first**
   where they can. Anything that's already installed is just hardened — we don't
   replace your nginx/Apache/MySQL.

---

## License

MIT — see [LICENSE](LICENSE).
