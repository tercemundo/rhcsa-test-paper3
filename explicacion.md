# Explicación del laboratorio RHCSA Test Paper 3

Este documento explica cómo se comunican las máquinas del laboratorio y cómo
agregar una nueva pregunta que afecte al nodo 1 (por ejemplo, configurar un
repositorio Flatpak), desde el enunciado en HTML hasta la corrección automática.

---

## 1. Comunicación entre las máquinas

El laboratorio consta de **3 máquinas virtuales** de AlmaLinux 10 levantadas con
Vagrant + VirtualBox:

| Máquina | Hostname | IP (eth1 host-only) | Rol |
|---|---|---|---|
| Workstation | `workstation` | `172.25.250.9` | Máquina de control, corrector y servidor web del examen |
| servera | `servera` → `node1.example.com` | `172.25.250.10` | Nodo donde se resuelven las tareas Q02–Q15 |
| serverb | `serverb` → `node2.example.com` | `172.25.250.11` | Nodo donde se resuelven las tareas Q16–Q21 |

### Redes

Cada VM tiene **dos interfaces de red**:

- **eth0 (NAT)**: salida a internet, usada por Vagrant para hacer `ssh` a las
  VMs y para que los invitados descarguen paquetes (`dnf`, `curl`, etc.).
  Puerta por defecto: `10.0.2.2`.
- **eth1 (host-only)**: red privada `172.25.250.0/24` entre las 3 VMs y el
  equipo anfitrión. Es la interfaz con IP fija que usan los scripts para
  comunicarse entre sí.

El host recibe la IP `172.25.250.1` en esta red, por lo que puede acceder al
examen desde el navegador en `http://172.25.250.9/`.

### SSH y acceso entre máquinas

- `vagrant/provision-common.sh` configura en las 3 VMs:
  - Contraseña de root (`radiowits`).
  - `PermitRootLogin yes` y `PasswordAuthentication yes` en
    `/etc/ssh/sshd_config.d/00-rhcsa-lab.conf`.
  - Entradas en `/etc/hosts` para `workstation`, `servera`/`node1` y
    `serverb`/`node2`.
- `vagrant/provision-workstation.sh` genera una clave SSH en la workstation y
  la copia a `root@servera` y `root@serverb` mediante `sshpass`, para que el
  corrector pueda entrar sin contraseña.
- `check.sh` se conecta a los nodos mediante `sshpass` con la contraseña
  definida en `ROOT_PASS="radiowits"`.

### Resumen del flujo de comunicación

```
Tu PC (host)
   ├─▶ http://172.25.250.9/  →  workstation (examen en HTML)
   └─▶ vagrant ssh           →  workstation (terminal de control)

workstation (172.25.250.9)
   ├─▶ ssh root@172.25.250.10  →  servera / node1 (tareas Q02–Q15)
   └─▶ ssh root@172.25.250.11  →  serverb / node2 (tareas Q16–Q21)
```

---

## 2. Cómo agregar una pregunta nueva que afecte al nodo 1

Supongamos que queremos agregar una tarea tipo: **"Configurar un repositorio
Flatpak en node1"**. A continuación se detalla cada paso.

### 2.1. En el HTML (enunciado del examen)

1. Crear un nuevo archivo, por ejemplo `html/question22.html`, con la consigna
   traducida al castellano.
2. Mantener la misma estructura que las demás preguntas: sidebar con temporizador
   y bloque `.content` con el `<h2>` y el `<p>` de la consigna.
3. Agregar el enlace en `html/index.html` dentro de la lista de tareas de
   `node1`:

```html
<div class="task"><input type="radio" /> Revisar <input type="radio" /> Hecho
<a href="question22.html">Configurar repositorio Flatpak</a></div>
```

4. Actualizar el contador `Task X of 21` si se desea, o dejarlo como referencia
   visual (no afecta la corrección automática).

Ejemplo de consigna en `question22.html`:

```html
<h2>Configurar repositorio Flatpak</h2>
<p>Instalar el soporte para Flatpak y agregar el repositorio de Flathub en
node1.</p>
```

### 2.2. En la workstation

La workstation es la máquina donde se prepara el escenario y donde se ejecuta
el corrector.

#### Archivos relevantes

- `env.sh`: ejecuta `workstation.sh` en la workstation.
- `workstation.sh`: copia `servera.sh` y `serverb.sh` a los nodos y los ejecuta
  por SSH.
- `check.sh`: el corrector que se ejecuta en la workstation.

#### Qué hacer en la workstation

Si la nueva pregunta requiere paquetes instalados en la workstation (por ejemplo
herramientas para generar claves o archivos de prueba), agrégalos en
`vagrant/provision-workstation.sh` o en `workstation.sh`.

Normalmente, para una tarea que solo afecta al nodo 1, **no es necesario tocar
la workstation**, salvo que quieras dejar archivos de prueba o scripts de
ayuda en `/root` o en algún directorio compartido.

### 2.3. En nodo 1 (servera)

El escenario inicial de los nodos se define en:

- `vagrant/provision-common.sh`: configuración común de las 3 VMs (red, SSH,
  paquetes base, SELinux, IPv4-only).
- `servera.sh`: script que deja servera en el estado inicial del examen
  (ejecutado por `workstation.sh` vía SSH).

#### Pasos para agregar el repositorio Flatpak en el estado inicial

1. Editar `servera.sh` y agregar, por ejemplo:

```bash
# Instalar soporte Flatpak y repositorio Flathub
dnf install -y flatpak
flatpak remote-add --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo
```

2. Si la tarea pide algo que el alumno debe verificar (por ejemplo, que el
   repo exista en `/etc/yum.repos.d/` o en la configuración de Flatpak), asegúrate
   de que `servera.sh` deje el sistema en el estado base esperado antes de que el
   alumno comience el examen.

3. `workstation.sh` copia `servera.sh` a `/root/remote_run.sh` en servera y lo
   ejecuta con `ssh`, por lo que cualquier cambio que hagas en `servera.sh`
   se aplicará automáticamente al levantar el laboratorio con `env.sh`.

### 2.4. El sshpass

El corrector `check.sh` necesita entrar por SSH a los nodos como root usando
contraseña. Para ello:

- En la workstation, `check.sh` define `ROOT_PASS="radiowits"`.
- Usa `sshpass -p "$ROOT_PASS" ssh ...` para ejecutar comandos remotos.
- La función `run_remote()` encapsula esto:

```bash
run_remote(){
  local host="$1"; shift
  sshpass -p "$ROOT_PASS" ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null root@"$host" "$@"
}
```

- `provision-common.sh` deja habilitado el login de root con contraseña en los
  nodos (`PermitRootLogin yes`, `PasswordAuthentication yes`).
- `provision-workstation.sh` instala `sshpass` en la workstation (desde EPEL 10).

Si agregas una nueva tarea, no necesitas cambiar nada relacionado con sshpass,
a menos que quieras conectarte a un host distinto o con otra contraseña.

### 2.5. Proceso de corrección

El script `check.sh` se ejecuta en la workstation (como root) y evalúa todas las
tareas definidas.

#### Flujo general

1. `need_root`: verifica que se ejecute como root.
2. `ensure_sshpass`: instala `sshpass` si no está presente (usando EPEL 10).
3. Para cada tarea, llama a `run_remote $NODE1 "<comando de verificación>"`.
4. Según el resultado, llama a `add_summary QXX Tarea PASS` o `FAIL`.
5. Al final imprime una tabla resumen, calcula el porcentaje y muestra PASS/FAIL.

#### Cómo agregar la verificación de tu nueva tarea

Supongamos que tu nueva tarea es la **Q22** (configurar repo Flatpak en node1).

1. Incrementa `TOTAL` si quieres que cuente en el porcentaje (por ejemplo de 20
   a 21), o deja `TOTAL=20` y agrega la verificación como extra (no recomendado
   si quieres que afecte la nota).

2. Agrega un bloque de verificación antes del resumen, por ejemplo:

```bash
# Q22 – Repositorio Flatpak
if run_remote $NODE1 "flatpak remotes | grep -q flathub"; then
  check_ok "Q22 Repositorio Flatpak configurado"
  add_summary Q22 Flatpak PASS
else
  check_fail "Q22 Repositorio Flatpak faltante"
  add_summary Q22 Flatpak FAIL
fi
```

3. El comando remoto se ejecuta en nodo1 a través de SSH con `sshpass`.
4. Al terminar, `check.sh` imprime:

```
Q     | Task                 | Result
------------------------------------------
Q22   | Flatpak              | PASS
------------------------------------------
TOTAL: X / Y  →  Z%
RESULT: PASS
```

El umbral de aprobación está definido en `PASS_THRESHOLD=70`.

---

## 3. Comandos útiles del laboratorio

```bash
# Levantar el laboratorio
vagrant up

# Preparar el escenario del examen
./env.sh

# Verificar que el escenario quedó bien armado
./verificar-escenario.sh

# Iniciar el examen (3 horas)
exam-timer start 180

# Corregir sin timer
./check.sh

# Entrar a los nodos
vagrant ssh servera
vagrant ssh serverb

# Acceder al examen desde el navegador del host
# http://172.25.250.9/
```

---

## 4. Resumen del flujo completo para una nueva tarea en nodo1

1. **HTML**: crear `html/question22.html` con la consigna y enlazarla desde
   `html/index.html`.
2. **servera.sh**: agregar los comandos para dejar el nodo en el estado inicial
   (ej. instalar Flatpak, agregar remoto).
3. **workstation.sh / provision-workstation.sh**: instalar paquetes de apoyo en
   la workstation si es necesario (opcional).
4. **check.sh**: agregar la función de verificación que se ejecuta por SSH con
   `sshpass` contra `172.25.250.10`.
5. **Levantar todo**: `vagrant up` + `./env.sh` para aplicar los cambios, y
   `./check.sh` para corregir.