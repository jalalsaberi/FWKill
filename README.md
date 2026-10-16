# FWKill

**🔥 Detect your Linux VPS and disable its default firewall rules — one by one with confirmation, or all at once**

[![](https://img.shields.io/badge/Version-v1.0.0-blue)](https://github.com/jalalsaberi/FWKill/releases)
[![](https://img.shields.io/badge/Licence-MIT-green)](https://github.com/jalalsaberi/FWKill/blob/main/LICENSE)

> [!CAUTION]
> **USE AT YOUR OWN RISK.**
> FWKill **removes the security layers that protect your server**. After it runs, every service listening on your VPS (databases, web panels, admin ports, SSH, etc.) may become reachable from the entire internet.
>
> - This project is provided **"as is", without any warranty** of any kind.
> - The author and contributors accept **no responsibility or liability** for any damage, data loss, downtime, hacking, account suspension, provider or Terms-of-Service violations, or any other consequence of using this script.
> - **Everything you do with this script is entirely on you.** If you do not fully understand what disabling a firewall means, **do not run it**.
> - It is your responsibility to make sure using it is allowed by your hosting provider, your organization, and the laws of your country.

## Support

🌟 If this project helped you, please give it a star! 🌟

<a href="https://nowpayments.io/donation/jalalsaberi" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>

- USDT (BEP20)
```
0x165aAc518A3c2Ca5a2108e923e767d3661FA88F3
```
- USDT (TRC20)
```
TKHNY5zze2PhSaQUGrEyoDz1E9fCG9hjh6
```
- [More Cryptocurrencies](https://nowpayments.io/donation?api_key=D8PCVB0-GRN4ZKB-HE7GFGC-84QRXA5&source=lk_donation&medium=referral)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Compatible OS](#compatible-os)
3. [Features](#features)
4. [Before You Run](#before-you-run)
5. [Options](#options)
6. [Usage Modes](#usage-modes)
7. [What It Detects](#what-it-detects)
8. [What Exactly Gets Changed](#what-exactly-gets-changed)
9. [NAT, VPN and Docker](#nat-vpn-and-docker)
10. [Backups & Restore](#backups--restore)
11. [Provider-Side Firewalls](#provider-side-firewalls)
12. [After Running: Stay Safe](#after-running-stay-safe)
13. [Troubleshooting & FAQ](#troubleshooting--faq)
14. [License](#license)

---

## Quick Start

Run as **root**. The script first shows a warning; in interactive mode you must type `yes` to continue.

**Interactive (recommended)** — shows every firewall it finds and asks before disabling each one:
```bash
bash <(curl -Ls https://raw.githubusercontent.com/jalalsaberi/FWKill/main/fwkill.sh)
```

**List only** — detect and show, change nothing:
```bash
bash <(curl -Ls https://raw.githubusercontent.com/jalalsaberi/FWKill/main/fwkill.sh) -l
```

**Disable everything** — no per-item questions (10-second abort countdown first):
```bash
bash <(curl -Ls https://raw.githubusercontent.com/jalalsaberi/FWKill/main/fwkill.sh) -y
```

Or download it and run it locally:
```bash
curl -Lo fwkill.sh https://raw.githubusercontent.com/jalalsaberi/FWKill/main/fwkill.sh
chmod +x fwkill.sh
sudo ./fwkill.sh
```

> [!TIP]
> Always run with `-l` first to see what will be touched.

## Compatible OS

| Family | Tested / Expected |
|---|---|
| Debian | ≥ 10 |
| Ubuntu | ≥ 18 |
| RHEL-based (CentOS, AlmaLinux, Rocky, Oracle Linux, Fedora) | ≥ 7 / current |
| openSUSE / SLES | best effort |
| Arch / Alpine / others | best effort (detection works; service handling depends on systemd) |

Works on KVM, VMware, Xen, Hyper-V and bare metal. On **OpenVZ / LXC** containers some changes may be refused by the host kernel — the script warns you when it detects a container.

## Features

- 🖥️ **System detection** — distro, release, family, kernel, architecture, virtualization, CPU, RAM, hostname
- ☁️ **Provider detection** — Oracle Cloud, AWS, Google Cloud, Azure, DigitalOcean, Hetzner, Vultr, Linode/Akamai, Alibaba, Tencent, Scaleway, OVH, Contabo (via DMI/hardware info and cloud-init)
- 🔍 **Finds every firewall layer** — UFW, firewalld, CSF/LFD, APF, Shorewall, fail2ban, nftables, iptables/ip6tables (nft and legacy backends), and boot-time rule restore
- ❓ **Interactive mode** — shows rules and asks `y/N` for each item
- ⚡ **Auto mode** (`-y`) — disables everything found
- 👀 **List mode** (`-l`) — dry run, changes nothing
- 🔐 **SSH-safe** — sets policies to `ACCEPT` *before* flushing rules, so your session doesn't drop
- 🌐 **Keeps NAT by default** — VPN masquerading (WireGuard, OpenVPN, Xray, …) and Docker port forwards keep working
- 🐳 **Docker-aware** — restarts Docker afterwards to rebuild its chains
- 🟠 **Oracle Cloud fix** — removes the default `REJECT` rules OCI images ship in `/etc/iptables/rules.v4`
- 💾 **Automatic backups** — every rule set and config is saved before it is touched
- ♻️ **Reboot-proof** — disables services and rule files that would bring the rules back on boot

## Before You Run

Please check all of these:

- [ ] You have **out-of-band access** (provider web console / VNC / rescue mode) in case you lose SSH.
- [ ] You know what is listening on your server:
  ```bash
  ss -tulpn
  ```
  Anything bound to `0.0.0.0` or `[::]` **will be exposed** after the firewall is off.
- [ ] Databases (MySQL, PostgreSQL, Redis, MongoDB…) and admin panels are protected by strong passwords or bound to `127.0.0.1`.
- [ ] Your hosting provider allows it.
- [ ] You have read the [disclaimer](#fwkill) and accept that **you alone are responsible**.

## Options

| Option | Description |
|---|---|
| *(none)* | Interactive mode: show each firewall and ask whether to disable it |
| `-l`, `--list` | List mode: detect and show only, change nothing |
| `-y`, `--yes` | Auto mode: disable everything found without asking per item |
| `--accept` | With `-y`: skip the 10-second warning countdown (for automation) |
| `--flush-nat` | Also flush the iptables `nat` table (**breaks VPN/Docker NAT** — see [below](#nat-vpn-and-docker)) |
| `-h`, `--help` | Show help |

Options can be combined, e.g. `-y --accept --flush-nat`.

## Usage Modes

### 1. Startup warning

Every run starts with a red warning banner.

| Mode | What you must do |
|---|---|
| Interactive | Type `yes` to continue — anything else exits without changes |
| `-y` | 10-second countdown — press `Ctrl+C` to abort (skip with `--accept`) |
| `-l` | Nothing — list mode never changes anything |

### 2. System report

```
==== System ====
  OS        : Ubuntu 22.04.4 LTS  (id=ubuntu, version=22.04, family=debian)
  Kernel    : 5.15.0-105-generic  arch=aarch64
  Virt      : kvm
  Hardware  : QEMU / Standard PC
  Provider  : Oracle Cloud (OCI)
  CPU / RAM : 4 cores / 23.4 GB
  Hostname  : my-vps
  Backups   : /root/firewall-backup-20261016-114512
```

### 3. Firewall scan

Each finding is shown with details, then you're asked:

```
==== Scanning firewalls ====

  ● iptables — 9 rules in filter table
      policies: -P INPUT ACCEPT -P FORWARD ACCEPT -P OUTPUT ACCEPT
      blocking rules (first 8):
      -A INPUT -j REJECT --reject-with icmp-host-prohibited
      -A FORWARD -j REJECT --reject-with icmp-host-prohibited
    Disable it? [y/N]: y
[+]     disabled.

  ● Boot-time rule restore (rules come back after reboot)
      netfilter-persistent service enabled
      /etc/iptables/rules.v4 contains DROP/REJECT rules
      (Oracle Cloud images ship restrictive rules here by default)
    Disable it? [y/N]: y
[+]     disabled.
```

The default answer is **No** — just pressing Enter skips the item.

### 4. Summary

```
==== Summary ====
  Found     : 2
  Disabled  : 2
  Skipped   : 0
  Backups   : /root/firewall-backup-20261016-114512
```

## What It Detects

| Item | Detected when |
|---|---|
| UFW | `ufw status` reports `active` |
| firewalld | service active or `firewall-cmd --state` is `running` |
| CSF + LFD | `csf` installed and active |
| APF | `apf` installed and `/etc/apf` exists |
| Shorewall / Shorewall6 | service active |
| fail2ban | service active (it bans IPs through the firewall) |
| nftables | native nft tables loaded, or `nftables` service enabled at boot |
| iptables / ip6tables | any non-default rule or non-`ACCEPT` policy in `filter`, `mangle` or `raw` |
| iptables-legacy / ip6tables-legacy | same, for the legacy backend if present |
| Boot-time restore | `netfilter-persistent`, `iptables.service` or `ip6tables.service` enabled, or `DROP`/`REJECT` rules in saved rule files |
| SELinux | `Enforcing` — shown as information only, **not changed** |

## What Exactly Gets Changed

| Item | Action |
|---|---|
| UFW | `ufw --force disable`, service stopped and disabled |
| firewalld | service stopped, disabled **and masked** |
| CSF / LFD | `csf -x`, both services stopped and disabled |
| APF | `apf -f`, service stopped and disabled |
| Shorewall | `shorewall clear`, service stopped and disabled |
| fail2ban | service stopped and disabled |
| nftables | native tables deleted (iptables-nft tables are left to the iptables step), service stopped and disabled |
| iptables / ip6tables | policies set to `ACCEPT`, `filter`/`mangle`/`raw`/`security` tables flushed and custom chains deleted; `nat` kept unless `--flush-nat` |
| Rule files | `/etc/iptables/rules.v4`, `rules.v6`, `/etc/sysconfig/iptables`, `ip6tables` replaced with an accept-all ruleset |
| Persistence services | `netfilter-persistent`, `iptables`, `ip6tables` services stopped and disabled |
| Docker | restarted if its chains were removed |

Nothing is uninstalled — packages stay on the system so you can turn them back on.

## NAT, VPN and Docker

By default FWKill **does not touch the `nat` table**. That table holds:

- `MASQUERADE` rules that let VPN clients (WireGuard, OpenVPN, L2TP, Xray, etc.) reach the internet
- Docker's published port forwards (`-p 8080:80`)
- any custom port forwarding

Clearing it does not make the server "more open" — it only breaks these features. Use `--flush-nat` only if you really want a completely empty ruleset; you will then need to restart your VPN services and Docker.

## Backups & Restore

Before anything is changed, the script saves it to:

```
/root/firewall-backup-YYYYMMDD-HHMMSS/
```

| File | Content |
|---|---|
| `iptables.rules`, `ip6tables.rules`, `*-legacy.rules` | output of `iptables-save` / `ip6tables-save` |
| `nftables-ruleset.nft` | full `nft list ruleset` |
| `nftables.conf` | copy of `/etc/nftables.conf` |
| `_etc_iptables_rules.v4` (etc.) | original saved rule files |
| `etc-ufw/`, `etc-firewalld/`, `etc-csf/`, `etc-apf/`, `etc-shorewall/` | config directories |
| `ufw-status.txt`, `firewalld-zones.txt` | rules in readable form |

If nothing was disabled, the empty backup folder is removed.

### Restore examples

> [!NOTE]
> Restoring is **your responsibility**. Replace `<backup>` with your backup folder.

```bash
# iptables / ip6tables
iptables-restore  < /root/<backup>/iptables.rules
ip6tables-restore < /root/<backup>/ip6tables.rules

# nftables (use this OR the iptables files above, not both)
nft -f /root/<backup>/nftables-ruleset.nft
systemctl enable --now nftables

# Saved rule files + persistence (Debian/Ubuntu)
cp /root/<backup>/_etc_iptables_rules.v4 /etc/iptables/rules.v4
cp /root/<backup>/_etc_iptables_rules.v6 /etc/iptables/rules.v6
systemctl enable --now netfilter-persistent

# Saved rule files + persistence (RHEL-based)
cp /root/<backup>/_etc_sysconfig_iptables /etc/sysconfig/iptables
systemctl enable --now iptables

# UFW
ufw enable

# firewalld
systemctl unmask firewalld && systemctl enable --now firewalld

# CSF
csf -e && systemctl enable --now csf lfd

# fail2ban
systemctl enable --now fail2ban
```

## Provider-Side Firewalls

FWKill only controls firewalls **inside** the VPS. Many providers also filter traffic **before** it reaches your server. If a port is still closed after running FWKill, open it in your provider's panel:

| Provider | Where |
|---|---|
| Oracle Cloud | Networking → VCN → Security Lists / Network Security Groups |
| AWS EC2 | EC2 → Security Groups (and Network ACLs) |
| Google Cloud | VPC network → Firewall |
| Azure | Network Security Group of the VM / NIC |
| Hetzner | Cloud Console → Firewalls |
| DigitalOcean | Networking → Firewalls |
| Vultr | Products → Firewall |
| Linode / Akamai | Cloud Firewalls |
| Alibaba / Tencent | Security Groups |

## After Running: Stay Safe

Your server is now open. Strongly recommended:

- Use **SSH keys** and disable password login (`PasswordAuthentication no`)
- Bind databases and internal services to `127.0.0.1`
- Use strong, unique passwords on every panel
- Keep the system updated (`apt upgrade` / `dnf upgrade`)
- Regularly check what's exposed: `ss -tulpn`
- Consider re-enabling a minimal firewall that only allows the ports you actually use

## Troubleshooting & FAQ

<details>
<summary><b>"Run as root" error</b></summary>

Run with `sudo`, or log in as root (`sudo -i`).
</details>

<details>
<summary><b>The port is still closed after running</b></summary>

1. Check the service is actually listening on `0.0.0.0` / `[::]`: `ss -tulpn | grep <port>`
2. Run `sudo bash fwkill.sh -l` again — it should report `Found: 0`.
3. Open the port in your [provider's firewall](#provider-side-firewalls).
</details>

<details>
<summary><b>Rules came back after reboot</b></summary>

Run the script again and answer **yes** to *Boot-time rule restore*. Also check for a custom script in `/etc/rc.local`, a cron `@reboot` job, or a control panel (cPanel, Plesk, aaPanel…) that manages its own firewall.
</details>

<details>
<summary><b>My VPN clients have no internet after running</b></summary>

You probably used `--flush-nat`. Restart your VPN service (e.g. `systemctl restart wg-quick@wg0`) so it re-adds its `MASQUERADE` rule, or restore `nat` from the backup.
</details>

<details>
<summary><b>Docker containers lost networking</b></summary>

`systemctl restart docker` — Docker rebuilds its chains on start. The script does this automatically when it detects Docker chains.
</details>

<details>
<summary><b>"Operation not permitted" on OpenVZ / LXC</b></summary>

Container VPSs share the host kernel; some netfilter operations are blocked by the host. Ask your provider, or use their panel firewall.
</details>

<details>
<summary><b>Does it uninstall anything?</b></summary>

No. Packages stay installed; only services are stopped/disabled and rules removed. There's nothing to uninstall for FWKill itself — it's a single script.
</details>

<details>
<summary><b>Can I use it in automation / cloud-init?</b></summary>

Yes: `bash fwkill.sh -y --accept`. You are still fully responsible for the result.
</details>

## License

This project is licensed under the [MIT License](https://github.com/jalalsaberi/FWKill/blob/main/LICENSE).

The MIT License provides the software **"AS IS", WITHOUT WARRANTY OF ANY KIND**. By using FWKill you accept that the authors are not liable for any claim, damages or other liability arising from its use.
