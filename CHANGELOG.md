# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).

The `ddos-protect update-check` command parses this file from `main` to detect
new releases. The first `## [x.y.z]` heading is treated as the latest version.

---

## [Unreleased]

<!--
Add entries here for in-progress work. They get promoted into a numbered
release section when a new version is cut.
-->

---

## [1.0.0] - 2026-06-06

Initial public release.

### Added
- **Cross-platform installer.** `install.sh` (Linux), `install.command`
  (macOS double-click shim), `install.ps1` (Windows) — colored menu, OS
  detection, per-module dry-run, full or selective module install.
- **One-liner bootstrap.** `curl -sSL …/bootstrap.sh | sudo bash` and
  `irm …/bootstrap.ps1 | iex` clone into `/opt/ddos-protect` /
  `C:\ProgramData\ddos-protect-src` and launch the installer.
- **Linux modules (15)**
  - `01-firewall` — iptables / nftables / ufw edge rules: per-IP SYN/ICMP/conn
    limits, drop invalid/XMAS/NULL, amplification-source-port blackhole
    (19/53/123/389/1900/11211/27015 …) with detect-listening short-circuit,
    IP whitelist from `/etc/ddos-protect/whitelist.txt`. Installs
    `ddos-allow <ip>` helper.
  - `02-sysctl` — SYN cookies, RFC1337, rp_filter, kptr_restrict, source-route
    off, martian log, kernel ASLR.
  - `03-fail2ban` — installs fail2ban if missing, drops in `jail.local` and
    custom `nginx-ddos` filter, disables jails for services that aren't present.
  - `04-sshd` — drop-in hardening; refuses to disable password auth if no
    `authorized_keys` is present.
  - `05-nginx`, `06-apache`, `07-mysql` — service hardening **only if installed**.
  - `08-email` — Postfix anti-relay/rate limits, Dovecot connection caps, Exim
    guidance.
  - `09-rootkit-scan` — rkhunter + chkrootkit + Lynis + optional ClamAV, results
    pushed to notification channels.
  - `10-audit` — read-only enumeration of listening sockets, SUID, cron,
    timers, `authorized_keys`, processes with deleted executables.
  - `11-unsafe-services` — opt-in disable for telnet/rsh/avahi/cups/rpcbind/snmpd/…
  - `12-cloudflare` — `ddos-cf on|off|block|unblock|list` + fail2ban action
    that pushes bans to a CF zone.
  - `13-notify` — 6-channel notification: Discord, Telegram, ntfy.sh, Slack,
    Gotify, generic webhook. Installs `ddos-notify` CLI + `ddos-notify`
    fail2ban action.
  - `14-monitor` — systemd timer (60s) sampling CPU/Mem/RX/TX/TCP-conn, alerts
    above thresholds with per-key cooldown.
  - `15-game-servers` — Minecraft Java/Bedrock, FiveM, TS3, Mumble, Source,
    Valheim, DayZ rate limits.
- **macOS modules (9)** — pf anchor, sysctl LaunchDaemon, brew fail2ban + pf
  banaction, sshd, audit, Cloudflare, notify, watcher LaunchDaemon, game-server
  pf anchor.
- **Windows modules (12)** — Firewall (`-Group "DDoS-Protect"` for clean
  removal), TCP/IP registry hardening + SMBv1 off, RDP NLA + lockout, MySQL,
  reversible UWP debloat (Candy Crush, Bing, Xbox, …), telemetry block
  (services + firewall, no hosts edits), Defender + ASR rules + quick scan,
  audit (suspicious services/tasks/autorun/WMI), unsafe-services, Cloudflare,
  notifications + 4625-burst Scheduled Task, realtime watcher Scheduled Task.
- **Master switch.** `ddos-protect on|off|status|restart` toggles the firewall
  hook, fail2ban, watcher, and 4625-alert task (Windows) without touching configs.
- **Status & ban inspection.** `ddos-protect bans` lists every banned IP grouped
  by source jail with active/lifetime counts, `--top` for top offenders, `--geo`
  for free GeoIP via ip-api.com. `ddos-protect stats` shows chain drop counters,
  last watcher sample, and top connected peers. `ddos-protect ban|unban <ip>`
  for manual intervention.
- **Uninstaller.** `uninstall.sh` / `uninstall.ps1` reverses every change from
  the `state.json` snapshot — restores registry values, re-registers UWP apps,
  re-enables services, removes firewall chain/group, archives `state.json`.

### Security
- `notify.env` and `cloudflare.env` written `0600` / ACL-locked to
  Administrators+SYSTEM.
- Reflection-vector source ports only blackholed when no matching local
  service is listening.
- Module 04 refuses to disable SSH password auth without a verified
  `authorized_keys` for the installing user (no lockout risk).

### Known limitations
- Windows Firewall has no per-source rate-limit primitive; game-port protection
  on Windows relies on the TCP/IP stack hardening (`TcpMaxHalfOpen`,
  `SynAttackProtect`) rather than per-IP `hashlimit`.
- ip-api.com free tier is capped at 45 lookups/min; `bans --geo` truncates at
  25 IPs and sleeps 300 ms between calls.
- No automatic update applies during install — the user is prompted by
  `ddos-protect update`.
