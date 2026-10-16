#!/usr/bin/env bash
# =============================================================================
#  fwkill.sh — detect the VPS (distro, release, virt, provider) and find every
#  active firewall layer, then disable them one by one (asks first) or all at
#  once with -y.  Everything is backed up before it is touched.
#
#  Usage:
#     sudo bash fwkill.sh          # interactive: show each firewall, ask y/n
#     sudo bash fwkill.sh -y       # disable everything found, no questions
#     sudo bash fwkill.sh -l       # list only, change nothing
#     sudo bash fwkill.sh -y --flush-nat   # also flush the NAT table (see note)
#     sudo bash fwkill.sh -y --accept      # skip the 10s warning countdown
#
#  WARNING: USE AT YOUR OWN RISK. This script removes the security layers that
#  protect your server. The author accepts no responsibility for any damage,
#  data loss, downtime, attacks, or provider/ToS issues. You run it on your own.
#
#  Note: by default the iptables "nat" table is NOT flushed, so MASQUERADE /
#  port-forward rules used by VPNs (WireGuard, OpenVPN, Xray...) and Docker
#  keep working. Only the filtering rules are removed.
# =============================================================================

set -u

# ---------- colors ----------
if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; C=$'\e[36m'; W=$'\e[1m'; N=$'\e[0m'
else
  R=; G=; Y=; B=; C=; W=; N=
fi

info()  { echo "${B}[*]${N} $*"; }
ok()    { echo "${G}[+]${N} $*"; }
warn()  { echo "${Y}[!]${N} $*"; }
err()   { echo "${R}[x]${N} $*" >&2; }
title() { echo; echo "${W}${C}==== $* ====${N}"; }

# ---------- args ----------
MODE="ask"        # ask | yes | list
FLUSH_NAT=0
ACCEPTED=0
for a in "$@"; do
  case "$a" in
    -y|--yes)   MODE="yes" ;;
    -l|--list)  MODE="list" ;;
    --flush-nat) FLUSH_NAT=1 ;;
    --accept)   ACCEPTED=1 ;;
    -h|--help)  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unknown option: $a"; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { err "Run as root (sudo bash $0)"; exit 1; }

# ---------- risk warning ----------
echo
echo "${R}${W}################################################################${N}"
echo "${R}${W}#                    !!!  WARNING  !!!                         #${N}"
echo "${R}${W}################################################################${N}"
echo "${Y} This script DISABLES the firewalls that protect this server.${N}"
echo "${Y} After it runs, every listening service may be reachable from${N}"
echo "${Y} the whole internet (databases, panels, admin ports...).${N}"
echo
echo " - USE AT YOUR OWN RISK. You are solely responsible for the result."
echo " - The author gives NO warranty and accepts NO liability for any"
echo "   damage, data loss, downtime, hacking, bans, or provider/ToS issues."
echo " - Make sure you have console/VNC access to this server in case"
echo "   something goes wrong, and know what is listening (ss -tulpn)."
echo " - Backups of all removed rules are saved, but restoring is YOUR job."
echo "${R}${W}################################################################${N}"
echo

case "$MODE" in
  list)
    info "List mode: nothing will be changed." ;;
  ask)
    read -r -p "${W}Type 'yes' to accept the risk and continue: ${N}" CONFIRM </dev/tty
    [[ ${CONFIRM,,} == "yes" ]] || { err "Not accepted. Exiting, nothing changed."; exit 1; } ;;
  yes)
    if [[ $ACCEPTED -eq 0 ]]; then
      warn "Auto mode (-y): everything found will be disabled."
      for i in 10 9 8 7 6 5 4 3 2 1; do
        printf "\r${Y}[!]${N} Starting in %2ds — press Ctrl+C to abort... " "$i"; sleep 1
      done; echo
    fi ;;
esac

BACKUP_DIR="/root/firewall-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

have()      { command -v "$1" >/dev/null 2>&1; }
svc_active(){ have systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }
svc_enabled(){ have systemctl && systemctl is-enabled --quiet "$1" 2>/dev/null; }
svc_exists(){ have systemctl && systemctl list-unit-files "$1.service" 2>/dev/null | grep -q "^$1.service"; }

svc_off() {   # stop + disable (+ optional mask)
  local s=$1 mask=${2:-0}
  have systemctl || { have service && service "$s" stop >/dev/null 2>&1; return; }
  systemctl stop "$s" >/dev/null 2>&1
  systemctl disable "$s" >/dev/null 2>&1
  [[ $mask -eq 1 ]] && systemctl mask "$s" >/dev/null 2>&1
}

ask() {   # ask "question" -> 0 = yes
  [[ $MODE == "yes" ]] && return 0
  [[ $MODE == "list" ]] && return 1
  local ans
  read -r -p "    ${W}Disable it? [y/N]: ${N}" ans </dev/tty
  [[ $ans =~ ^[Yy]([Ee][Ss])?$ ]]
}

# =============================================================================
#  1. SYSTEM DETECTION
# =============================================================================
title "System"

OS_ID="unknown"; OS_LIKE=""; OS_NAME="unknown"; OS_VER=""
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID=${ID:-unknown}; OS_LIKE=${ID_LIKE:-}; OS_NAME=${PRETTY_NAME:-$NAME}; OS_VER=${VERSION_ID:-}
elif [[ -r /etc/redhat-release ]]; then
  OS_NAME=$(cat /etc/redhat-release); OS_ID="rhel"
fi

case " $OS_ID $OS_LIKE " in
  *" debian "*|*" ubuntu "*)               FAMILY="debian" ;;
  *" rhel "*|*" fedora "*|*" centos "*)    FAMILY="rhel" ;;
  *" suse "*|*" opensuse "*)               FAMILY="suse" ;;
  *" arch "*)                              FAMILY="arch" ;;
  *" alpine "*)                            FAMILY="alpine" ;;
  *)                                       FAMILY="other" ;;
esac

dmi() { [[ -r /sys/class/dmi/id/$1 ]] && tr -d '\n' < "/sys/class/dmi/id/$1" 2>/dev/null; }
VENDOR=$(dmi sys_vendor); PRODUCT=$(dmi product_name); ASSET=$(dmi chassis_asset_tag); BIOS=$(dmi bios_vendor)

VIRT="unknown"
if have systemd-detect-virt; then VIRT=$(systemd-detect-virt 2>/dev/null || echo none)
elif [[ -f /proc/user_beancounters ]]; then VIRT="openvz"
elif grep -qa container=lxc /proc/1/environ 2>/dev/null; then VIRT="lxc"
fi

# provider guess
PROVIDER="unknown"
HINT="$VENDOR $PRODUCT $ASSET $BIOS"
case "$HINT" in
  *OracleCloud*)                 PROVIDER="Oracle Cloud (OCI)" ;;
  *Amazon*|*EC2*)                PROVIDER="AWS EC2" ;;
  *Google*)                      PROVIDER="Google Cloud" ;;
  *Microsoft*)                   PROVIDER="Microsoft Azure" ;;
  *DigitalOcean*)                PROVIDER="DigitalOcean" ;;
  *Hetzner*)                     PROVIDER="Hetzner" ;;
  *Vultr*)                       PROVIDER="Vultr" ;;
  *Linode*|*Akamai*)             PROVIDER="Linode/Akamai" ;;
  *Alibaba*)                     PROVIDER="Alibaba Cloud" ;;
  *Tencent*)                     PROVIDER="Tencent Cloud" ;;
  *Scaleway*)                    PROVIDER="Scaleway" ;;
  *OVH*)                         PROVIDER="OVH" ;;
  *Contabo*)                     PROVIDER="Contabo" ;;
esac
if [[ $PROVIDER == "unknown" ]] && have cloud-id; then
  CID=$(cloud-id 2>/dev/null) && [[ -n $CID && $CID != "none" ]] && PROVIDER="$CID (cloud-init)"
fi

echo "  OS        : $OS_NAME  (id=$OS_ID, version=$OS_VER, family=$FAMILY)"
echo "  Kernel    : $(uname -r)  arch=$(uname -m)"
echo "  Virt      : $VIRT"
echo "  Hardware  : ${VENDOR:-?} / ${PRODUCT:-?}"
echo "  Provider  : $PROVIDER"
echo "  CPU / RAM : $(nproc 2>/dev/null) cores / $(awk '/MemTotal/{printf "%.1f GB",$2/1048576}' /proc/meminfo)"
echo "  Hostname  : $(hostname)"
echo "  Backups   : $BACKUP_DIR"

case "$VIRT" in
  openvz|lxc|lxc-libvirt)
    warn "Container VPS ($VIRT): some kernel firewall changes may be refused by the host." ;;
esac

# =============================================================================
#  2. DETECTION + DISABLE HANDLERS
# =============================================================================
FOUND=0; DISABLED=0; SKIPPED=0
DOCKER_TOUCHED=0

item() {  # item "name" "details"
  FOUND=$((FOUND+1))
  echo
  echo "  ${Y}●${N} ${W}$1${N}"
  [[ -n ${2:-} ]] && echo "$2" | sed 's/^/      /'
}
done_()  { DISABLED=$((DISABLED+1)); ok "    disabled."; }
skip_()  { SKIPPED=$((SKIPPED+1)); [[ $MODE != "list" ]] && info "    skipped."; }

title "Scanning firewalls"

# ---------- UFW ----------
if have ufw && ufw status 2>/dev/null | grep -qi "Status: active"; then
  item "UFW (Uncomplicated Firewall) — active" "$(ufw status numbered 2>/dev/null | head -20)"
  if ask; then
    ufw status verbose > "$BACKUP_DIR/ufw-status.txt" 2>&1
    cp -a /etc/ufw "$BACKUP_DIR/etc-ufw" 2>/dev/null
    ufw --force disable >/dev/null 2>&1
    svc_off ufw
    done_
  else skip_; fi
fi

# ---------- firewalld ----------
if svc_active firewalld || { have firewall-cmd && firewall-cmd --state 2>/dev/null | grep -q running; }; then
  item "firewalld — running" "$(firewall-cmd --list-all 2>/dev/null | head -20)"
  if ask; then
    firewall-cmd --list-all-zones > "$BACKUP_DIR/firewalld-zones.txt" 2>&1
    cp -a /etc/firewalld "$BACKUP_DIR/etc-firewalld" 2>/dev/null
    svc_off firewalld 1
    done_
  else skip_; fi
fi

# ---------- CSF / LFD ----------
if have csf && { svc_active csf || svc_active lfd || csf -l >/dev/null 2>&1; }; then
  item "CSF (ConfigServer Firewall) + LFD" ""
  if ask; then
    cp -a /etc/csf "$BACKUP_DIR/etc-csf" 2>/dev/null
    csf -x >/dev/null 2>&1
    svc_off csf; svc_off lfd
    done_
  else skip_; fi
fi

# ---------- APF ----------
if have apf && [[ -d /etc/apf ]]; then
  item "APF (Advanced Policy Firewall)" ""
  if ask; then
    cp -a /etc/apf "$BACKUP_DIR/etc-apf" 2>/dev/null
    apf -f >/dev/null 2>&1
    svc_off apf
    done_
  else skip_; fi
fi

# ---------- Shorewall ----------
for sw in shorewall shorewall6; do
  if svc_active "$sw"; then
    item "$sw — running" ""
    if ask; then
      cp -a "/etc/$sw" "$BACKUP_DIR/etc-$sw" 2>/dev/null
      "$sw" clear >/dev/null 2>&1
      svc_off "$sw"
      done_
    else skip_; fi
  fi
done

# ---------- fail2ban ----------
if svc_active fail2ban; then
  jails=$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:\s*//p')
  item "fail2ban — running (bans IPs via firewall)" "jails: ${jails:-?}"
  if ask; then
    svc_off fail2ban
    done_
  else skip_; fi
fi

# ---------- nftables (native rules) ----------
if have nft; then
  # ignore tables created by iptables-nft (they show up as "table ip filter" etc.
  # and are handled in the iptables section) — count only native ones
  NFT_RULES=$(nft list ruleset 2>/dev/null)
  NFT_NATIVE=$(echo "$NFT_RULES" | grep -E '^table ' | grep -vE '^table (ip|ip6) (filter|nat|mangle|raw|security) \{' )
  if [[ -n $NFT_NATIVE ]] || svc_enabled nftables; then
    item "nftables — $( [[ -n $NFT_NATIVE ]] && echo 'native tables loaded' || echo 'service enabled at boot')" \
         "${NFT_NATIVE:-<no native tables right now>}"
    if ask; then
      echo "$NFT_RULES" > "$BACKUP_DIR/nftables-ruleset.nft"
      [[ -f /etc/nftables.conf ]] && cp -a /etc/nftables.conf "$BACKUP_DIR/"
      # delete only native tables, keep iptables-nft ones for the iptables step
      while read -r _ fam name _; do
        [[ -z ${fam:-} ]] && continue
        nft delete table "$fam" "$name" 2>/dev/null
      done <<< "$NFT_NATIVE"
      svc_off nftables
      done_
    else skip_; fi
  fi
fi

# ---------- iptables / ip6tables (nft + legacy backends) ----------
iptables_has_rules() {  # $1 = binary ; true if filter table is not "empty ACCEPT"
  local b=$1
  "$b" -S 2>/dev/null | grep -qvE '^-P (INPUT|FORWARD|OUTPUT) ACCEPT$' && return 0
  for t in mangle raw; do
    "$b" -t "$t" -S 2>/dev/null | grep -qvE '^-P [A-Z]+ ACCEPT$' && return 0
  done
  return 1
}

iptables_reset() {   # $1 = binary
  local b=$1 save=${1/tables/tables-save}
  have "$save" && "$save" > "$BACKUP_DIR/$b.rules" 2>/dev/null
  # 1) open policies FIRST so SSH never drops
  for ch in INPUT FORWARD OUTPUT; do "$b" -P "$ch" ACCEPT 2>/dev/null; done
  # 2) flush filtering tables
  "$b" -F 2>/dev/null; "$b" -X 2>/dev/null; "$b" -Z 2>/dev/null
  for t in mangle raw security; do
    "$b" -t "$t" -F 2>/dev/null; "$b" -t "$t" -X 2>/dev/null
  done
  if [[ $FLUSH_NAT -eq 1 ]]; then
    "$b" -t nat -F 2>/dev/null; "$b" -t nat -X 2>/dev/null
  fi
}

for bin in iptables ip6tables iptables-legacy ip6tables-legacy; do
  have "$bin" || continue
  # skip legacy if it's just the same backend as the default
  if [[ $bin == *-legacy ]] && ! "$bin" -S >/dev/null 2>&1; then continue; fi
  if iptables_has_rules "$bin"; then
    count=$("$bin" -S 2>/dev/null | grep -c '^-A')
    pol=$("$bin" -S 2>/dev/null | grep '^-P' | tr '\n' ' ')
    preview=$("$bin" -S 2>/dev/null | grep -E 'REJECT|DROP' | head -8)
    item "$bin — $count rules in filter table" "policies: $pol
${preview:+blocking rules (first 8):
$preview}"
    "$bin" -S 2>/dev/null | grep -q DOCKER && warn "    Docker chains present — Docker will be restarted afterwards to rebuild its rules."
    if ask; then
      "$bin" -S 2>/dev/null | grep -q DOCKER && DOCKER_TOUCHED=1
      iptables_reset "$bin"
      done_
    else skip_; fi
  fi
done

# ---------- Persistence: things that restore rules at boot ----------
PERSIST_DESC=""
svc_enabled netfilter-persistent && PERSIST_DESC+="netfilter-persistent service enabled"$'\n'
svc_enabled iptables  && PERSIST_DESC+="iptables.service enabled (iptables-services)"$'\n'
svc_enabled ip6tables && PERSIST_DESC+="ip6tables.service enabled"$'\n'
for f in /etc/iptables/rules.v4 /etc/iptables/rules.v6 /etc/sysconfig/iptables /etc/sysconfig/ip6tables; do
  [[ -s $f ]] && grep -qE 'REJECT|DROP' "$f" && PERSIST_DESC+="$f contains DROP/REJECT rules"$'\n'
done

if [[ -n $PERSIST_DESC ]]; then
  [[ $PROVIDER == Oracle* ]] && PERSIST_DESC+="(Oracle Cloud images ship restrictive rules here by default)"$'\n'
  item "Boot-time rule restore (rules come back after reboot)" "${PERSIST_DESC%$'\n'}"
  if ask; then
    for f in /etc/iptables/rules.v4 /etc/iptables/rules.v6 /etc/sysconfig/iptables /etc/sysconfig/ip6tables; do
      [[ -f $f ]] || continue
      cp -a "$f" "$BACKUP_DIR/$(echo "$f" | tr / _)"
      printf '*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n' > "$f"
    done
    svc_off netfilter-persistent
    svc_off iptables
    svc_off ip6tables
    done_
  else skip_; fi
fi

# ---------- Docker rebuild ----------
if [[ $DOCKER_TOUCHED -eq 1 ]] && svc_active docker; then
  info "Restarting Docker to recreate its networking rules..."
  systemctl restart docker && ok "Docker restarted."
fi

# ---------- informational: SELinux ----------
if have getenforce && [[ $(getenforce 2>/dev/null) == "Enforcing" ]]; then
  echo
  warn "SELinux is Enforcing. It's not a firewall, but it can block services from"
  warn "binding to non-standard ports. Check with: semanage port -l"
fi

# =============================================================================
#  3. SUMMARY
# =============================================================================
title "Summary"
echo "  Found     : $FOUND"
if [[ $MODE == "list" ]]; then
  echo "  (list mode — nothing changed)"
  rmdir "$BACKUP_DIR" 2>/dev/null
else
  echo "  Disabled  : $DISABLED"
  echo "  Skipped   : $SKIPPED"
  [[ $DISABLED -gt 0 ]] && echo "  Backups   : $BACKUP_DIR" || rmdir "$BACKUP_DIR" 2>/dev/null
fi
[[ $FOUND -eq 0 ]] && ok "No active firewall found on this server."

echo
warn "This only covers firewalls INSIDE the VPS. Provider-side firewalls"
warn "(AWS Security Groups, OCI Security Lists, GCP/Azure/Hetzner/DO cloud"
warn "firewalls) must be opened from the provider's control panel."
[[ $FLUSH_NAT -eq 0 && $MODE != "list" ]] && info "NAT table was kept (VPN/Docker masquerading still works). Use --flush-nat to clear it too."
echo
