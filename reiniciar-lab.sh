#!/bin/bash
#
# reiniciar-lab.sh - Reinicia el laboratorio RHCSA sin destruir las VMs.
#
# Uso:
#   ./reiniciar-lab.sh
#
# Qué hace:
#   1. Apaga las VMs existentes (vagrant halt).
#   2. Las vuelve a encender (vagrant up).
#   3. No ejecuta env.sh ni modifica el estado interno de las VMs.
#
# Ideal para cuando las VMs ya están creadas y solo querés reiniciarlas
# (por ejemplo, tras un cambio de red o para solucionar problemas
# temporales) sin perder el escenario del examen.
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
echo "  REINICIANDO LABORATORIO RHCSA TEST PAPER 3"
echo "=============================================="
echo ""

echo "-> Paso 1/2: Apagando las VMs..."
vagrant halt

echo ""
echo "-> Paso 2/2: Encendiendo las VMs nuevamente..."
vagrant up

echo ""
echo "=============================================="
echo "  ¡LABORATORIO REINICIADO!"
echo "=============================================="
echo ""
echo "Las VMs están encendidas. El estado interno no se modificó."
echo ""
echo "Para entrar a la workstation:"
echo "  vagrant ssh"
echo ""
echo "Para entrar a los servidores:"
echo "  vagrant ssh servera"
echo "  vagrant ssh serverb"
echo ""
