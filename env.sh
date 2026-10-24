#!/bin/bash
#
# env.sh - Arma el escenario del examen. Ejecutar EN LA WORKSTATION.
#
#   cd /root/rhcsa-test-paper3 && ./env.sh
#
# Version para el laboratorio Vagrant: usa los scripts LOCALES (workstation.sh,
# servera.sh, serverb.sh) en vez de descargar los originales de GitHub, que
# estan pensados para otro entorno (discos /dev/vdb, reinicios automaticos...).
#
# Opciones (variables de entorno):
#   INSTALL_GUI=1  instala "Server with GUI" en servera/serverb (pesado)
#   REBOOT=1       reinicia servera/serverb al terminar
set -u

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

[[ $EUID -eq 0 ]] || exec sudo -E bash "$0" "$@"

[[ -f "$DIR/workstation.sh" ]] || { echo "No encuentro $DIR/workstation.sh"; exit 1; }

# workstation.sh ya se encarga de lanzar servera.sh y serverb.sh por SSH (paso 7/7)
bash "$DIR/workstation.sh"
rc=$?

if (( rc == 0 )); then
  echo "[env] Escenario listo. Siguiente: exam-timer start 180"
else
  echo "[env] workstation.sh termino con error ($rc). Revisa la salida de arriba."
fi
exit $rc
