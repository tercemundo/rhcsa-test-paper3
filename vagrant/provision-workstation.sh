#!/usr/bin/env bash
#
# provision-workstation.sh - Solo para la VM "workstation"
#
# - Instala sshpass (lo usa check.sh) y herramientas de apoyo
# - Deja el repo en /root/rhcsa-test-paper3 (git clone + archivos locales encima)
# - Instala exam-timer y rhcsa-check en /usr/local/bin
# - Genera una clave SSH y la copia a root@servera y root@serverb
#
# Variables: ROOT_PASS, SUBNET

set -euo pipefail

ROOT_PASS="${ROOT_PASS:-radiowits}"
SUBNET="${SUBNET:-172.25.250}"
REPO_URL="https://github.com/tercemundo/rhcsa-test-paper3.git"
LAB_DIR="/root/rhcsa-test-paper3"
SERVERS=(servera serverb)

log(){ echo "[workstation] $*"; }
warn(){ echo "[workstation] ADVERTENCIA: $*" >&2; }
retry(){ local n=0; until "$@"; do n=$((n+1)); (( n >= 5 )) && return 1; sleep 5; done; }

# ---------------------------------------------------------------------------
log "Paquetes (EPEL 10 para sshpass)"
# ---------------------------------------------------------------------------
retry dnf install -y --setopt=install_weak_deps=False \
  git curl openssh-clients procps-ng tmux util-linux

# AlmaLinux 10 trae epel-release en el repo extras. Si no estuviera, se usa el
# RPM oficial de EPEL 10 como respaldo.
if ! retry dnf install -y epel-release; then
  warn "epel-release no esta disponible; probando el RPM oficial de EPEL 10"
  retry dnf install -y \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm \
    || warn "No se pudo instalar el repositorio EPEL 10"
fi

retry dnf install -y sshpass \
  || warn "sshpass no se instalo; check.sh intentara instalarlo por su cuenta"

# ---------------------------------------------------------------------------
log "Repositorio en $LAB_DIR"
# ---------------------------------------------------------------------------
if [[ ! -d "$LAB_DIR/.git" ]]; then
  rmdir "$LAB_DIR" 2>/dev/null || true
  git clone --depth 1 "$REPO_URL" "$LAB_DIR" \
    || { warn "git clone fallo; se usaran solo los archivos locales"; mkdir -p "$LAB_DIR"; }
fi

# Los archivos locales (junto al Vagrantfile) pisan a los del clon:
# asi exam-timer.sh y tus modificaciones de check.sh/env.sh tienen prioridad.
shopt -s nullglob
for f in /tmp/lab-upload-*; do
  [[ -d "$f" ]] && continue
  name="${f#/tmp/lab-upload-}"
  install -m 0755 "$f" "$LAB_DIR/$name"
  log "Copiado: $name"
done

# Archivos web que van dentro de html/ (tema oscuro, CSS/JS propios).
# Sin esto, workstation.sh desplegaria un clon del repo sin esos archivos.
if compgen -G "/tmp/lab-upload-html/*" >/dev/null 2>&1; then
  mkdir -p "$LAB_DIR/html"
  for f in /tmp/lab-upload-html/*; do
    [[ -f "$f" ]] || continue
    install -m 0644 "$f" "$LAB_DIR/html/$(basename "$f")"
    log "Copiado: html/$(basename "$f")"
  done
fi

# Por si el repo se descargo en Windows con finales de linea CRLF
for f in "$LAB_DIR"/*.sh; do
  sed -i 's/\r$//' "$f"
  chmod +x "$f"
done

[[ -f "$LAB_DIR/check.sh" ]] || warn "No existe $LAB_DIR/check.sh"
[[ -f "$LAB_DIR/exam-timer.sh" ]] || warn "No existe $LAB_DIR/exam-timer.sh"

# Atajos globales (exam-timer.sh resuelve su carpeta con readlink -f, asi que
# sigue encontrando check.sh a traves del enlace simbolico)
ln -sf "$LAB_DIR/exam-timer.sh" /usr/local/bin/exam-timer
ln -sf "$LAB_DIR/check.sh"      /usr/local/bin/rhcsa-check

# ---------------------------------------------------------------------------
log "httpd y firewalld (examen accesible desde el host en http://172.25.250.9)"
# ---------------------------------------------------------------------------
# El examen se publica con httpd en el puerto 80. Si firewalld queda activo en
# la zona "public" sin el servicio http permitido, el firewall RECHAZA las
# conexiones y desde el navegador del host se ve "no se puede acceder a este
# sitio" (el puerto responde "No route to host"). El permiso es permanente,
# asi que sobrevive reinicios de la VM.
retry dnf install -y --setopt=install_weak_deps=False httpd || warn "No se pudo instalar httpd"
systemctl enable --now httpd >/dev/null 2>&1 || warn "No se pudo activar httpd"

# Publica el examen en /var/www/html para que ya se pueda entrar desde el host
# a http://172.25.250.9 despues de "vagrant up" (env.sh/workstation.sh vuelven
# a desplegarlo, es idempotente).
if [[ -d "$LAB_DIR/html" ]]; then
  mkdir -p /var/www/html
  cp -a "$LAB_DIR/html/." /var/www/html/
  chown -R apache:apache /var/www/html 2>/dev/null || true
  log "Examen publicado en /var/www/html ($(ls /var/www/html | wc -l) archivos)"
fi

if command -v firewall-cmd >/dev/null 2>&1; then
  # El permiso permanente se puede dejar aunque el daemon no este corriendo:
  # asi, si firewalld arranca despues (lo hace workstation.sh durante env.sh),
  # el puerto 80 ya queda abierto.
  firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
  if firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --reload >/dev/null 2>&1 || true
    log "firewalld: servicio http habilitado (puerto 80 abierto)"
  else
    log "firewalld: servicio http habilitado de forma permanente (puerto 80)"
  fi
fi

# ---------------------------------------------------------------------------
log "Clave SSH de root y configuracion de cliente"
# ---------------------------------------------------------------------------
mkdir -p /root/.ssh
chmod 700 /root/.ssh
[[ -f /root/.ssh/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519

# Evita avisos si destruis y recreas las VMs (cambian las claves de host)
cat > /root/.ssh/config <<EOF
Host servera serverb node1 node2 ${SUBNET}.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chmod 600 /root/.ssh/config

wait_ssh(){
  local h=$1
  for _ in $(seq 1 60); do
    if (exec 3<>"/dev/tcp/$h/22") 2>/dev/null; then return 0; fi
    sleep 2
  done
  return 1
}

for h in "${SERVERS[@]}"; do
  if ! wait_ssh "$h"; then
    warn "$h no responde en el puerto 22"
    continue
  fi
  if command -v sshpass >/dev/null; then
    sshpass -p "$ROOT_PASS" ssh-copy-id -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null -i /root/.ssh/id_ed25519.pub "root@$h" >/dev/null 2>&1 \
      && log "Clave SSH copiada a root@$h" \
      || warn "No se pudo copiar la clave a root@$h (revisa la contrasena de root)"
  else
    warn "Sin sshpass: no se pudo copiar la clave a $h"
  fi
done

# ---------------------------------------------------------------------------
log "Mensaje de bienvenida (motd)"
# ---------------------------------------------------------------------------
cat > /etc/motd <<'EOF'

  ===== RHCSA Lab :: WORKSTATION =====
   sudo -i                       pasa a root
   cd /root/rhcsa-test-paper3    carpeta del lab
   ./env.sh                      prepara el escenario del examen
   exam-timer start 180          inicia el examen (3 h)
   exam-timer live               cuenta regresiva
   exam-timer finish             corrige y muestra tu tiempo
   rhcsa-check                   solo corrige (sin timer)

   Servidores:  ssh root@servera   |   ssh root@serverb
  ====================================

EOF

# ---------------------------------------------------------------------------
log "Resumen de conectividad"
# ---------------------------------------------------------------------------
printf '%-14s %-8s %-8s\n' "Host" "Ping" "SSH root"
for h in "${SERVERS[@]}"; do
  p="FAIL"; s="FAIL"
  ping -c1 -W2 "$h" >/dev/null 2>&1 && p="OK"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$h" true >/dev/null 2>&1 && s="OK"
  printf '%-14s %-8s %-8s\n' "$h" "$p" "$s"
done

log "Listo. Entra con: vagrant ssh   y luego: sudo -i"
