#!/usr/bin/env bash
#
# provision-common.sh - Se ejecuta en las 3 VMs (workstation, servera, serverb)
#
# Variables (las pasa el Vagrantfile):
#   ROLE       workstation | servera | serverb
#   ROOT_PASS  password de root (por defecto radiowits)
#   SUBNET     prefijo de la red host-only (por defecto 172.25.250)

set -euo pipefail

ROLE="${ROLE:?Falta la variable ROLE}"
ROOT_PASS="${ROOT_PASS:-radiowits}"
SUBNET="${SUBNET:-172.25.250}"

log(){ echo "[common:$ROLE] $*"; }

# ---------------------------------------------------------------------------
log "Hostname"
# ---------------------------------------------------------------------------
hostnamectl set-hostname "$ROLE"

# ---------------------------------------------------------------------------
log "Password de root y SSH con contrasena (necesario para check.sh y env.sh)"
# ---------------------------------------------------------------------------
echo "root:${ROOT_PASS}" | chpasswd

# El Include de sshd_config.d va primero en RHEL 9 y en SSH gana la primera
# directiva que aparece, por eso el prefijo 00-.
cat > /etc/ssh/sshd_config.d/00-rhcsa-lab.conf <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
EOF
sshd -t
systemctl restart sshd

# ---------------------------------------------------------------------------
log "/etc/hosts"
# ---------------------------------------------------------------------------
sed -i '/# BEGIN RHCSA-LAB/,/# END RHCSA-LAB/d' /etc/hosts
cat >> /etc/hosts <<EOF
# BEGIN RHCSA-LAB
${SUBNET}.9   workstation
${SUBNET}.10  servera node1.example.com node1
${SUBNET}.11  serverb node2.example.com node2
# END RHCSA-LAB
EOF

# ---------------------------------------------------------------------------
log "Paquetes base"
# ---------------------------------------------------------------------------
retry(){ local n=0; until "$@"; do n=$((n+1)); (( n >= 5 )) && return 1; sleep 5; done; }
retry dnf install -y --setopt=install_weak_deps=False \
  curl tar bzip2 rsync vim-enhanced bash-completion bind-utils

# ---------------------------------------------------------------------------
log "Verificacion de red"
# ---------------------------------------------------------------------------
echo "--- Interfaces ---"
ip -4 -brief addr show

MY_IP="$(ip -4 -o addr show | awk '{print $4}' | grep -E "^${SUBNET}\." || true)"
if [[ -z "$MY_IP" ]]; then
  echo "[common:$ROLE] ADVERTENCIA: no se ve ninguna IP ${SUBNET}.x. Revisa la interfaz host-only (eth1)." >&2
else
  log "Red host-only OK: $MY_IP"
fi

if curl -fsS --max-time 10 -o /dev/null https://github.com; then
  log "Salida a internet OK (NAT)"
else
  echo "[common:$ROLE] ADVERTENCIA: sin salida a internet por NAT." >&2
fi

log "Listo."
