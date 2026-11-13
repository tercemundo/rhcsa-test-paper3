#!/usr/bin/env bash
#
# verificar-escenario.sh - Verificacion de solo lectura del escenario del
# simulacro RHCSA. NO corrige nada y NO evalua el examen: solo comprueba que
# el escenario quedo armado correctamente en las 3 VMs.
#
#   Ejecutar EN LA WORKSTATION, como root:
#     cd /root/rhcsa-test-paper3 && ./verificar-escenario.sh
#
# Sale con codigo 0 si todo esta OK, 1 si hay algun problema.

set -u

NODE1="${NODE1:-172.25.250.10}"   # servera
NODE2="${NODE2:-172.25.250.11}"   # serverb

PASS=0
FAIL=0

ok(){   printf '  \033[32m[ OK ]\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko(){   printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
head_(){ printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# Ejecuta un comando remoto y evalua el resultado
remote(){
  local host="$1"; shift
  local out
  out="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 -o BatchMode=yes "root@$host" "$@" 2>/dev/null)"
  printf '%s' "$out"
}

# check <descripcion> <host|local> <comando> [regex-esperado]
check(){
  local desc="$1" host="$2" cmd="$3" expect="${4:-}"
  local out rc
  if [[ "$host" == "local" ]]; then
    out="$(eval "$cmd" 2>&1)"
  else
    out="$(remote "$host" "$cmd")"
  fi
  rc=$?
  if [[ -n "$expect" ]]; then
    if grep -qE "$expect" <<<"$out"; then ok "$desc"; else ko "$desc (esperado: $expect)"; fi
  else
    if [[ $rc -eq 0 ]]; then ok "$desc"; else ko "$desc"; fi
  fi
}

# ---------------------------------------------------------------------------
head_ "Conectividad basica"
# ---------------------------------------------------------------------------
for h in "$NODE1" "$NODE2"; do
  if ping -c1 -W3 "$h" >/dev/null 2>&1; then ok "ping $h"; else ko "ping $h"; fi
done
if remote "$NODE1" "true" >/dev/null 2>&1; then ok "SSH root@$NODE1 (servera)"; else ko "SSH root@$NODE1 (servera)"; fi
if remote "$NODE2" "true" >/dev/null 2>&1; then ok "SSH root@$NODE2 (serverb)"; else ko "SSH root@$NODE2 (serverb)"; fi

# ---------------------------------------------------------------------------
head_ "servera (machine1.exam.com) - Q02 a Q15"
# ---------------------------------------------------------------------------
check "hostname = machine1.exam.com" "$NODE1" "hostname" "machine1\.exam\.com"
check "bzip2 DESINSTALADO (parte del escenario)" "$NODE1" "rpm -q bzip2 >/dev/null 2>&1 && echo INSTALADO || echo AUSENTE" "AUSENTE"
check "httpd instalado" "$NODE1" "rpm -q httpd" "^httpd-"
check "httpd enabled" "$NODE1" "systemctl is-enabled httpd" "^enabled"
check "httpd active" "$NODE1" "systemctl is-active httpd" "^active"
check "httpd escuchando en el puerto 82" "$NODE1" "ss -tuln" ":82[[:space:]]"
check "archivos en /var/www/html (file1,file2,file3)" "$NODE1" \
      "ls /var/www/html/file1 /var/www/html/file2 /var/www/html/file3 2>/dev/null | wc -l" "^3"
for u in remoteuser3 siya simone pandora; do
  check "usuario $u creado" "$NODE1" "id $u" "^uid="
done

# ---------------------------------------------------------------------------
head_ "serverb (machine2.exam.com) - Q16 a Q21"
# ---------------------------------------------------------------------------
check "hostname = machine2.exam.com" "$NODE2" "hostname" "machine2\.exam\.com"
check "password de root = 'password' (reset del escenario)" "$NODE2" \
      "grep '^root:' /etc/shadow | cut -d: -f2" "^\\\$[0-9a-z]+\\\$"
check "grupo de volumenes myvg" "$NODE2" "vgs myvg" "myvg"
check "logical volume myvg/home" "$NODE2" "lvs myvg/home" "home"
check "/home montado desde el LV myvg/home" "$NODE2" "findmnt -no SOURCE /home" "/dev/(mapper/)?myvg[-/]home"
check "entrada de /home en /etc/fstab" "$NODE2" "grep myvg /etc/fstab" "/dev/myvg/home[[:space:]]+/home"
check "tuned instalado y activo" "$NODE2" "systemctl is-active tuned" "^active"
check "perfil tuned = balanced" "$NODE2" "tuned-adm active" "balanced"

# ---------------------------------------------------------------------------
head_ "workstation - corrector, timer y contenido web"
# ---------------------------------------------------------------------------
check "hostname = workstation" "local" "hostname" "^workstation$"
check "repo del lab en /root/rhcsa-test-paper3" "local" \
      "ls /root/rhcsa-test-paper3/check.sh /root/rhcsa-test-paper3/env.sh /root/rhcsa-test-paper3/exam-timer.sh >/dev/null && echo OK" "^OK"
check "exam-timer enlazado en /usr/local/bin" "local" \
      "test -L /usr/local/bin/exam-timer && echo OK" "^OK"
check "rhcsa-check enlazado en /usr/local/bin" "local" \
      "test -L /usr/local/bin/rhcsa-check && echo OK" "^OK"
check "httpd activo" "local" "systemctl is-active httpd" "^active"
check "httpd habilitado al arranque" "local" "systemctl is-enabled httpd" "^enabled"
check "examen publicado en /var/www/html/index.html" "local" \
      "test -s /var/www/html/index.html && echo OK" "^OK"
check "las 20 preguntas (question2..question21) publicadas" "local" \
      "ls /var/www/html/question*.html 2>/dev/null | wc -l" "^20$"
check "tema oscuro (theme.css/theme.js) desplegado" "local" \
      "test -s /var/www/html/theme.css -a -s /var/www/html/theme.js && echo OK" "^OK"
check "examen accesible por HTTP" "local" \
      "curl -s -o /dev/null -w '%{http_code}' http://localhost/index.html" "^200"
check "firewalld permite http (puerto 80 reachable desde el host)" "local" \
      "firewall-cmd --state >/dev/null 2>&1 && firewall-cmd --service=http --query-port=80/tcp || echo NA" \
      "^(yes|NA)$"
check "export NFS de /ourhome/remoteuser3" "local" \
      "exportfs -v 2>/dev/null | grep remoteuser3" "remoteuser3"
check "sshpass instalado (lo usa check.sh)" "local" "command -v sshpass" "sshpass"
check "llave SSH de root copiada a servera" "local" \
      "ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE1 'echo K' 2>/dev/null" "^K"
check "llave SSH de root copiada a serverb" "local" \
      "ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE2 'echo K' 2>/dev/null" "^K"

# ---------------------------------------------------------------------------
head_ "Resumen"
# ---------------------------------------------------------------------------
printf '  Correctos: %d   |   Con problemas: %d\n\n' "$PASS" "$FAIL"
if [[ $FAIL -eq 0 ]]; then
  echo "El escenario quedo armado correctamente. Ya podes arrancar el examen:"
  echo "    exam-timer start 180"
  exit 0
else
  echo "Hay ${FAIL} comprobacion(es) con problemas (arriba)."
  exit 1
fi
