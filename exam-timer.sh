#!/usr/bin/env bash
#
# exam-timer.sh - Cuenta regresiva para el simulacro RHCSA
#
# Uso (en la WORKSTATION, como root):
#   ./exam-timer.sh start [minutos]   Inicia el examen (por defecto 180 min = 3 h)
#   ./exam-timer.sh status            Muestra el tiempo restante una vez
#   ./exam-timer.sh live              Cuenta regresiva en vivo (usar en otra terminal)
#   ./exam-timer.sh finish            Terminas antes: corre check.sh y muestra tu tiempo
#   ./exam-timer.sh stop              Cancela el timer sin corregir
#
# Variables opcionales:
#   AUTO_CHECK=no   -> al terminar el tiempo NO ejecuta check.sh automaticamente
#
# Al agotarse el tiempo avisa con `wall` (30, 10, 5 y 1 minuto antes y al final)
# y ejecuta check.sh guardando el resultado en /root/resultado_examen.txt

set -u

STATE="/root/.rhcsa_timer"
DIR="$(dirname "$(readlink -f "$0")")"
CHECK="$DIR/check.sh"
REPORT="/root/resultado_examen.txt"
AUTO_CHECK="${AUTO_CHECK:-yes}"

need_root(){ [[ $EUID -eq 0 ]] || { echo "Ejecutar como root"; exit 1; }; }

fmt(){
  local s=$1
  (( s < 0 )) && s=0
  printf '%02d:%02d:%02d' $(( s/3600 )) $(( s%3600/60 )) $(( s%60 ))
}

# Carga START, END y PID desde el archivo de estado
# shellcheck source=/dev/null
load(){ [[ -f "$STATE" ]] && source "$STATE"; }

remaining(){ echo $(( END - $(date +%s) )); }

strip_colors(){ sed 's/\x1b\[[0-9;]*m//g'; }

run_check(){
  if [[ -x "$CHECK" || -f "$CHECK" ]]; then
    bash "$CHECK" 2>&1 | tee >(strip_colors > "$REPORT")
  else
    echo "No se encontro $CHECK"
  fi
}

cmd_start(){
  local min="${1:-180}"
  [[ "$min" =~ ^[0-9]+$ ]] || { echo "Los minutos deben ser un numero entero"; exit 1; }

  if [[ -f "$STATE" ]]; then
    load
    if (( $(remaining) > 0 )); then
      echo "Ya hay un examen en curso. Quedan $(fmt "$(remaining)")."
      echo "Usa './exam-timer.sh stop' para cancelarlo."
      exit 1
    fi
  fi

  local start end
  start=$(date +%s)
  end=$(( start + min*60 ))
  printf 'START=%s\nEND=%s\n' "$start" "$end" > "$STATE"

  # Lanza el vigilante en segundo plano
  setsid nohup "$0" _watch >/dev/null 2>&1 &
  echo "PID=$!" >> "$STATE"

  echo "Examen iniciado: $min minutos."
  echo "Termina a las: $(date -d "@$end" '+%H:%M:%S')"
  echo "Ver tiempo restante: ./exam-timer.sh status   (o 'live' en otra terminal)"
}

cmd_status(){
  [[ -f "$STATE" ]] || { echo "No hay un examen en curso."; exit 0; }
  load
  local r; r=$(remaining)
  if (( r <= 0 )); then
    echo "Tiempo agotado."
  else
    echo "Tiempo restante: $(fmt "$r")"
  fi
}

cmd_live(){
  [[ -f "$STATE" ]] || { echo "No hay un examen en curso."; exit 0; }
  load
  trap 'echo; exit 0' INT
  while :; do
    local r; r=$(remaining)
    printf '\r  Tiempo restante: %s   ' "$(fmt "$r")"
    (( r <= 0 )) && { echo; echo "Tiempo agotado."; break; }
    sleep 1
  done
}

cmd_stop(){
  [[ -f "$STATE" ]] || { echo "No hay un examen en curso."; exit 0; }
  load
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null
  rm -f "$STATE"
  echo "Timer cancelado."
}

cmd_finish(){
  [[ -f "$STATE" ]] || { echo "No hay un examen en curso."; exit 1; }
  load
  local used=$(( $(date +%s) - START ))
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null
  rm -f "$STATE"
  echo "Terminaste en: $(fmt "$used")"
  echo
  run_check
  echo
  echo "Tiempo utilizado: $(fmt "$used")"
}

# Proceso interno en segundo plano: avisos + autocorreccion
cmd_watch(){
  load
  local total=$(( END - START ))
  local warned=" "
  while :; do
    local r; r=$(remaining)
    (( r <= 0 )) && break
    for t in 1800 600 300 60; do
      # Solo avisa umbrales menores a la duracion total, una unica vez
      if (( t < total && r <= t )) && [[ "$warned" != *" $t "* ]]; then
        warned+="$t "
        wall "RHCSA: quedan $(( t/60 )) minuto(s)" 2>/dev/null
      fi
    done
    sleep 5
  done

  wall "RHCSA: TIEMPO TERMINADO" 2>/dev/null
  rm -f "$STATE"
  if [[ "$AUTO_CHECK" == "yes" ]]; then
    run_check > /dev/null 2>&1
    wall "RHCSA: resultado guardado en $REPORT" 2>/dev/null
  fi
}

need_root
case "${1:-}" in
  start)  cmd_start "${2:-180}" ;;
  status) cmd_status ;;
  live)   cmd_live ;;
  stop)   cmd_stop ;;
  finish) cmd_finish ;;
  _watch) cmd_watch ;;
  *)
    sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
