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

# El Include de sshd_config.d va primero en RHEL/AlmaLinux 9 y 10; en SSH gana
# la primera directiva que aparece, por eso el prefijo 00-.
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
log "SELinux: contextos y deshabilitado"
# ---------------------------------------------------------------------------
# El perfil de red que escribe Vagrant (eth1.nmconnection) queda con contexto
# SELinux user_tmp_t. Con SELinux enforcing, NetworkManager no puede renombrar
# ese archivo, nmcli falla y la interfaz host-only conserva el gateway que
# Vagrant le pone (quedandose sin salida a internet). Primero se corrigen los
# contextos y despues se deshabilita SELinux.
if command -v restorecon >/dev/null 2>&1; then
  restorecon -RFv /etc/NetworkManager/system-connections/ 2>/dev/null || true
fi

setenforce 0 2>/dev/null || true
if [[ -f /etc/selinux/config ]]; then
  sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
fi
# Parametro de arranque adicional, por si /etc/selinux/config no alcanza
if [[ -f /etc/default/grub ]] && ! grep -q 'selinux=0' /etc/default/grub; then
  sed -i 's/^\(GRUB_CMDLINE_LINUX="[^"]*\)"/\1 selinux=0"/' /etc/default/grub
  if [[ -f /boot/grub2/grub.cfg ]]; then
    grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 || true
  elif [[ -f /boot/grub/grub.cfg ]]; then
    grub2-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
  fi
fi
log "SELinux: $(getenforce 2>/dev/null || echo 'no disponible') (deshabilitado al reiniciar)"

# ---------------------------------------------------------------------------
log "Red solo IPv4 (NAT como ruta por defecto, IPv6 deshabilitado)"
# ---------------------------------------------------------------------------
# Vagrant escribe GATEWAY=<primer IP de la red host-only> en la interfaz
# host-only (plantilla network_static.erb de los guests RedHat). Eso genera una
# ruta por defecto que compite con la del NAT y se queda con el trafico de
# salida: dnf/curl se quedan sin internet aunque el NAT funcione. Se corrige:
#   - la interfaz host-only pierde el gateway y nunca es ruta por defecto
#   - la interfaz NAT (10.0.2.x) queda como unica ruta por defecto
#   - IPv6 se deshabilita y el DNS queda fijo en 8.8.8.8 / 1.1.1.1
#
# El orden importa: IPv6 se desactiva antes de tocar NetworkManager y el
# DNS se escribe al final, porque cada vez que NM reconfigura una interfaz
# regenera /etc/resolv.conf con los DNS que tenia en el perfil.

# IPv6 deshabilitado a nivel kernel (efecto inmediato) y persistente
cat > /etc/sysctl.d/99-rhcsa-ipv4-only.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl --system >/dev/null 2>&1 || true
for dev in $(ls /sys/class/net 2>/dev/null); do
  [[ "$dev" == "lo" ]] && continue
  echo 1 > "/proc/sys/net/ipv6/conf/${dev}/disable_ipv6" 2>/dev/null || true
done

NAT_IF=""
HOSTONLY_IF=""
for dev in $(ls /sys/class/net 2>/dev/null); do
  [[ "$dev" == "lo" ]] && continue
  if ip -4 -o addr show dev "$dev" 2>/dev/null | grep -q "inet ${SUBNET}\."; then
    HOSTONLY_IF="$dev"
  elif ip -4 -o addr show dev "$dev" 2>/dev/null | grep -qE 'inet 10\.0\.2\.'; then
    NAT_IF="$dev"
  fi
done

con_uuid_for_dev(){
  nmcli -t -f UUID,DEVICE con show --active 2>/dev/null \
    | awk -F: -v d="$1" '$2 == d {print $1; exit}'
}

# --- NAT: DNS fijo + IPv6 off (se re-aplica sin bajar la interfaz) ---
if [[ -n "$NAT_IF" ]]; then
  nat_uuid="$(con_uuid_for_dev "$NAT_IF")"
  if [[ -n "$nat_uuid" ]]; then
    # NO se hace "nmcli con up" en la NAT: el SSH de Vagrant entra por ahi y
    # reiniciar la interfaz cortaria la conexion del provisioner.
    nmcli con mod "$nat_uuid" ipv6.method disabled \
      ipv4.ignore-auto-dns yes ipv4.dns "8.8.8.8,1.1.1.1" >/dev/null 2>&1 \
      || echo "[common:$ROLE] ADVERTENCIA: no se pudo ajustar el perfil NM de $NAT_IF" >&2
    nmcli dev reapply "$NAT_IF" >/dev/null 2>&1 || true
  fi
fi

# --- Host-only: sin gateway y nunca como ruta por defecto ---
if [[ -n "$HOSTONLY_IF" ]]; then
  ho_uuid="$(con_uuid_for_dev "$HOSTONLY_IF")"
  if [[ -n "$ho_uuid" ]]; then
    # Sin gateway + never-default: la red host-only queda solo para trafico
    # entre VMs. Reactivar eth1 no corta el SSH (entra por el NAT).
    nmcli con mod "$ho_uuid" ipv4.never-default yes ipv4.gateway "" \
      ipv6.method disabled >/dev/null 2>&1 \
      || echo "[common:$ROLE] ADVERTENCIA: no se pudo ajustar el perfil NM de $HOSTONLY_IF" >&2
    nmcli con up "$ho_uuid" >/dev/null 2>&1 || true
  fi
fi

# Borra cualquier ruta por defecto que no sea la de la interfaz NAT
ip -4 route show default | awk -v nat="$NAT_IF" '
  { gw=""; dev=""; for (i=1; i<=NF; i++) { if ($i=="via") gw=$(i+1); if ($i=="dev") dev=$(i+1) }
    if (dev != "" && dev != nat) print gw, dev }' \
  | while read -r gw dev; do
      ip route del default via "$gw" dev "$dev" 2>/dev/null || true
    done

# DNS solo IPv4 (resolvers publicos fijos) - se escribe al final para que
# ninguna reconfiguracion posterior de NetworkManager lo pise.
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\noptions timeout:2 attempts:2\n' > /etc/resolv.conf
chmod 644 /etc/resolv.conf

log "Rutas IPv4 resultantes:"
ip -4 route show | sed 's/^/    /'

# ---------------------------------------------------------------------------
log "Paquetes base"
# ---------------------------------------------------------------------------
retry(){ local n=0; until "$@"; do n=$((n+1)); (( n >= 5 )) && return 1; sleep 5; done; }
# lvm2/parted/e2fsprogs: necesarios para las tareas de LVM de serverb.
# policycoreutils-python-utils: aporta semanage para la tarea de SELinux (Q04).
retry dnf install -y --setopt=install_weak_deps=False \
  curl tar bzip2 rsync vim-enhanced bash-completion bind-utils \
  lvm2 parted e2fsprogs policycoreutils-python-utils

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

if curl -4 -fsS --max-time 15 -o /dev/null https://github.com; then
  log "Salida a internet OK por IPv4 (NAT)"
else
  echo "[common:$ROLE] ADVERTENCIA: sin salida a internet por IPv4 (NAT)." >&2
fi

if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
  log "Ping a 8.8.8.8 OK"
else
  echo "[common:$ROLE] ADVERTENCIA: no responde el ping a 8.8.8.8." >&2
fi

if getent hosts mirrors.almalinux.org >/dev/null 2>&1; then
  log "Resolucion DNS OK (8.8.8.8 / 1.1.1.1)"
else
  echo "[common:$ROLE] ADVERTENCIA: no resuelve DNS." >&2
fi

if ip -6 route show default | grep -q .; then
  echo "[common:$ROLE] ADVERTENCIA: queda una ruta por defecto IPv6." >&2
else
  log "Sin ruta por defecto IPv6 (laboratorio 100% IPv4)"
fi

log "Listo."
