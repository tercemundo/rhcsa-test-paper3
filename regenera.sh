#!/bin/bash
#
# regenera.sh - Regenera todo el laboratorio RHCSA Test Paper 3 desde cero.
#
# Uso:
#   ./regenera.sh
#
# Qué hace:
#   1. Destruye todas las VMs existentes (vagrant destroy -f).
#   2. Levanta las 3 VMs de AlmaLinux 10 desde cero (vagrant up).
#   3. Ejecuta env.sh automáticamente (AUTO_ENV=1) para preparar
#      el escenario del examen en workstation, servera y serverb.
#
# Requisitos:
#   - Estar ubicado en la raíz del repositorio (junto al Vagrantfile).
#   - Vagrant y VirtualBox instalados y funcionando.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f Vagrantfile ]]; then
  echo "ERROR: No se encontró Vagrantfile en $(pwd)." >&2
  echo "Ejecutá este script desde la raíz del repositorio." >&2
  exit 1
fi

if ! command -v vagrant >/dev/null 2>&1; then
  echo "ERROR: Vagrant no está instalado." >&2
  exit 1
fi

if ! command -v VBoxManage >/dev/null 2>&1; then
  echo "ERROR: VirtualBox no está instalado o no está en el PATH." >&2
  exit 1
fi

echo "=============================================="
echo "  REGENERANDO LABORATORIO RHCSA TEST PAPER 3"
echo "=============================================="
echo ""

echo "-> Paso 1/3: Deteniendo y destruyendo VMs existentes..."
vagrant destroy -f

echo ""
echo "-> Paso 2/3: Levantando las 3 VMs de AlmaLinux 10 desde cero..."
echo "   (servera, serverb y workstation)"
echo ""

AUTO_ENV=1 vagrant up

echo ""
echo "=============================================="
echo "  ¡LABORATORIO REGENERADO CON ÉXITO!"
echo "=============================================="
echo ""
echo "Próximos pasos para iniciar el examen:"
echo ""
echo "  1. vagrant ssh                 # entra a la workstation"
echo "  2. sudo -i                     # pasa a root"
echo "  3. cd /root/rhcsa-test-paper3  # carpeta del lab"
echo "  4. ./verificar-escenario.sh    # opcional: verifica el escenario"
echo "  5. exam-timer start 180        # inicia el examen (3 horas)"
echo ""
echo "Para acceder al examen desde el navegador del host:"
echo "  http://172.25.250.9/"
echo ""
