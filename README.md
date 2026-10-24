# RHCSA Test Paper 3 – Simulacro de examen con autocorrección

Simulacro práctico del examen **RHCSA (EX200)** para practicar en tu propio laboratorio.
Un script prepara el escenario en las máquinas, vos resolvés las tareas a mano y otro script
(`check.sh`) **corrige automáticamente** y te da un porcentaje y un veredicto PASS/FAIL.

> Fork de [`codexchangee/rhcsa-test-paper3`](https://github.com/codexchangee/rhcsa-test-paper3).
> Este README documenta el repo; los puntos marcados con ⚠️ son cosas que debés confirmar
> leyendo los scripts correspondientes antes de usarlos.

---

## Índice

1. [Contenido del repositorio](#1-contenido-del-repositorio)
2. [Arquitectura y roles](#2-arquitectura-y-roles)
3. [Requisitos](#3-requisitos)
4. [Instalación automatizada con Vagrant (recomendada)](#4-instalación-automatizada-con-vagrant-recomendada)
5. [Instalación manual paso a paso](#5-instalación-manual-paso-a-paso)
6. [Cómo se usa (flujo del examen)](#6-cómo-se-usa-flujo-del-examen)
7. [Tareas que se evalúan](#7-tareas-que-se-evalúan)
8. [Timer de examen](#8-timer-de-examen)
9. [Problemas frecuentes](#9-problemas-frecuentes)
10. [Advertencias de seguridad](#10-advertencias-de-seguridad)
11. [Limitaciones conocidas del corrector](#11-limitaciones-conocidas-del-corrector)

---

## 1. Contenido del repositorio

| Archivo / carpeta | Se ejecuta en | Para qué sirve |
|---|---|---|
| `env.sh` | workstation | Prepara el escenario: descarga `workstation.sh`, `servera.sh` y `serverb.sh` y los ejecuta (el primero local, los otros por SSH). |
| `workstation.sh` | workstation (lo lanza `env.sh`) | Prepara la máquina de control. ⚠️ Verificar contenido. |
| `servera.sh` | servera (lo lanza `env.sh` por SSH) | Deja servera en el estado inicial del examen. ⚠️ Verificar contenido. |
| `serverb.sh` | serverb (lo lanza `env.sh` por SSH) | Deja serverb en el estado inicial del examen. ⚠️ Verificar contenido. |
| `check.sh` | workstation | **Corrector**: se conecta a node1 y node2 por SSH, evalúa 20 tareas y muestra el resultado. |
| `paper-check.sh` | workstation | ⚠️ Verificar. Por el nombre, probablemente complementa la corrección o el enunciado. |
| `html/` | tu navegador | ⚠️ Verificar. Probablemente el enunciado del examen en versión web. |
| `exam-timer.sh` | workstation | **Nuevo**: cuenta regresiva con avisos y autocorrección (ver [sección 8](#8-timer-de-examen)). |
| `Vagrantfile` | tu PC | **Nuevo**: levanta las 3 VMs de VirtualBox con NAT + host-only (ver [sección 4](#4-instalación-automatizada-con-vagrant-recomendada)). |
| `vagrant/provision-common.sh` | las 3 VMs (lo lanza Vagrant) | **Nuevo**: root/SSH, `/etc/hosts`, paquetes base y verificación de red. |
| `vagrant/provision-workstation.sh` | workstation (lo lanza Vagrant) | **Nuevo**: sshpass, repo, atajos `exam-timer` y `rhcsa-check`, claves SSH. |
| `.gitattributes` / `.gitignore` | Git | **Nuevo**: finales de línea LF en los `.sh` e ignora `.vagrant/`. |

---

## 2. Arquitectura y roles

Se necesitan **3 máquinas** en la misma red: una de control y dos servidores a configurar.

```
                      Red 172.25.250.0/24
 ┌────────────────┐     ┌────────────────────┐     ┌────────────────────┐
 │  WORKSTATION   │     │  servera = node1   │     │  serverb = node2   │
 │ 172.25.250.9   │────▶│  172.25.250.10     │     │  172.25.250.11     │
 │ (control y     │ SSH │  (tareas Q02–Q15)  │     │  (tareas Q16–Q21)  │
 │  corrector)    │────▶│                    │     │                    │
 └────────────────┘     └────────────────────┘     └────────────────────┘
```

| Rol | Hostname / alias | IP | Qué hace | Quién lo usa |
|---|---|---|---|---|
| **Workstation** | `workstation` | `172.25.250.9` (sugerida) | Ejecuta `env.sh` para armar el escenario, `check.sh` para corregir y `exam-timer.sh` para cronometrar. Desde acá también te conectás por SSH a los servidores. | Alumno y corrector |
| **servera** (llamado **node1** en `check.sh`) | `servera` → debe terminar como `node1.example.com` | `172.25.250.10` | Servidor donde resolvés las tareas **Q02 a Q15**: red, repos, httpd, usuarios, cron, NTP, autofs, contenedores, etc. | Alumno (examinado) |
| **serverb** (llamado **node2** en `check.sh`) | `serverb` | `172.25.250.11` | Servidor donde resolvés las tareas **Q16 a Q21**: contraseña de root, repos, tuned, swap, LVM, resize de `/home`. | Alumno (examinado) |

> ⚠️ La equivalencia `servera = node1` y `serverb = node2` es una deducción: `env.sh` usa los nombres
> `servera`/`serverb` y `check.sh` usa las IPs `.10` y `.11` como `node1`/`node2`. Confirmala en
> `servera.sh` y `serverb.sh`.

---

## 3. Requisitos

### Sistema operativo

| Máquina | SO recomendado | Motivo |
|---|---|---|
| workstation | RHEL 9, Rocky Linux 9 o AlmaLinux 9 (también Fedora) | Los scripts usan `dnf`/`yum` para instalar `sshpass`. |
| servera / serverb | RHEL 9, Rocky Linux 9 o AlmaLinux 9 | Las tareas incluyen `dnf`, SELinux, `firewalld`, `tuned`, `podman`, LVM y `autofs`. |

### Recursos sugeridos por VM

| Máquina | CPU | RAM | Disco principal | Discos extra |
|---|---|---|---|---|
| workstation | 1–2 | 2 GB | 20 GB | — |
| servera | 1–2 | 2 GB | 20 GB | ⚠️ Según `servera.sh` |
| serverb | 1–2 | 2 GB | 20 GB | 1 o 2 discos de 2–5 GB sin usar (LVM, swap y resize). ⚠️ Confirmar con `serverb.sh` |

### Software en la workstation

| Paquete | Para qué | Instalación |
|---|---|---|
| `sshpass` | `check.sh` entra por SSH con contraseña | Lo instala solo `check.sh`, o a mano: `dnf install -y sshpass` |
| `openssh-clients` | Cliente SSH | `dnf install -y openssh-clients` |
| `curl` | `env.sh` descarga los scripts | `dnf install -y curl` |
| `git` | Clonar este repo | `dnf install -y git` |

### Red e internet

| Necesidad | Detalle |
|---|---|
| Subred | Las tres VMs deben estar en `172.25.250.0/24` (red interna o host-only). |
| Internet | Hace falta para que `env.sh` descargue los scripts y para la tarea Q15 (descargar la imagen `codesxchange/watcher` con Podman). Agregá un segundo adaptador NAT. |
| Nombres del laboratorio de Red Hat | Q03/Q17 buscan `content.example.com` en `/etc/yum.repos.d` y Q09 busca `classroom.example.com` en `/etc/chrony.conf`. Fuera del aula oficial hay que simularlos (ver paso 5.7). |

---

## 4. Instalación automatizada con Vagrant (recomendada)

Con un solo `vagrant up` se crean **3 VMs de VirtualBox**, cada una con **dos interfaces de red**
(NAT para internet + host-only para verse entre ellas), con root/SSH configurados, `/etc/hosts`
completo y la workstation lista con el corrector y el timer. Si preferís hacerlo a mano, saltá a la
[sección 5](#5-instalación-manual-paso-a-paso).

### 4.1 Qué se crea

| VM | Rol | eth0 | eth1 (host-only) | CPU / RAM | Discos extra sin usar |
|---|---|---|---|---|---|
| `servera` | node1 · tareas Q02–Q15 | NAT (internet) | `172.25.250.10` | 1 / 2 GB | 1 × 2 GB (ajustable) |
| `serverb` | node2 · tareas Q16–Q21 | NAT (internet) | `172.25.250.11` | 1 / 2 GB | 2 × 5 GB (ajustable) |
| `workstation` | corrector + timer | NAT (internet) | `172.25.250.9` | 1 / 1.5 GB | — |

Tu PC (el host) recibe la IP `172.25.250.1` en la red host-only, así que también podés hacer
`ssh` a las VMs desde tu máquina. Las VMs se llaman `rhcsa-servera`, `rhcsa-serverb` y
`rhcsa-workstation` en VirtualBox.

> ⚠️ Los tamaños de los discos extra son una estimación. Ajustá `disks:` en el `NODES` del
> `Vagrantfile` según lo que pidan `servera.sh` y `serverb.sh`.

### 4.2 Requisitos del equipo anfitrión

| Requisito | Detalle |
|---|---|
| VirtualBox | Instalado y funcionando. |
| Vagrant | 2.3.4 o superior. Usá una versión que soporte tu versión de VirtualBox. |
| Arquitectura | x86_64 (Intel/AMD). No sirve en Mac con Apple Silicon. |
| RAM libre | Unos 6 GB para las 3 VMs. |
| Disco libre | Unos 25–30 GB. |
| Internet | Para bajar la box (`rockylinux/9`), los paquetes y el repo. |

### 4.3 Autorizar la red host-only (solo Linux y macOS)

VirtualBox solo permite redes host-only dentro de `192.168.56.0/21` salvo que autorices otro rango.
Hacelo una sola vez (en Windows no hace falta):

```bash
sudo mkdir -p /etc/vbox
echo '* 172.25.250.0/24' | sudo tee -a /etc/vbox/networks.conf
```

El `Vagrantfile` verifica esto antes de `vagrant up` y, si falta, se detiene con este mismo aviso.

### 4.4 Archivos a copiar al repo

Copiá estos archivos a la **raíz** de tu clon (junto a `check.sh`, `env.sh`, etc.):

| Archivo | Para qué sirve |
|---|---|
| `Vagrantfile` | Define las 3 VMs, sus redes, discos y provisionado. |
| `vagrant/provision-common.sh` | Se ejecuta en las 3 VMs: hostname, root/SSH, `/etc/hosts`, paquetes base, verificación de red. |
| `vagrant/provision-workstation.sh` | Solo workstation: sshpass, repo, atajos, claves SSH, motd. |
| `exam-timer.sh` | El timer (se copia a la workstation). |
| `.gitattributes` | Fuerza finales de línea LF en los `.sh` (evita errores si clonás en Windows). |
| `.gitignore` | Ignora la carpeta `.vagrant/`. |

Estructura resultante:

```
rhcsa-test-paper3/
├── Vagrantfile
├── vagrant/
│   ├── provision-common.sh
│   └── provision-workstation.sh
├── exam-timer.sh
├── check.sh  env.sh  paper-check.sh  workstation.sh  servera.sh  serverb.sh
├── html/
├── .gitattributes
└── .gitignore
```

### 4.5 Levantar el laboratorio

```bash
cd rhcsa-test-paper3
vagrant up                 # crea y provisiona servera, serverb y workstation (en ese orden)
```

Con `AUTO_ENV=1` también ejecuta `env.sh` al final (en PowerShell: `$env:AUTO_ENV=1; vagrant up`):

```bash
AUTO_ENV=1 vagrant up
```

Después, para empezar el examen:

| Paso | Comando | Dónde |
|---|---|---|
| 1 | `vagrant ssh` | Tu PC → entra a la workstation (es la VM primaria) |
| 2 | `sudo -i` | workstation → pasa a root |
| 3 | `cd /root/rhcsa-test-paper3 && ./env.sh` | Solo si no usaste `AUTO_ENV=1` |
| 4 | `exam-timer start 180` | Inicia el cronómetro de 3 horas |
| 5 | `vagrant ssh servera` / `vagrant ssh serverb` | Tu PC (otra terminal) → resolvés las tareas con `sudo -i` |
| 6 | `exam-timer finish` | workstation → corrige y muestra tu tiempo |

`exam-timer` y `rhcsa-check` son atajos globales a `exam-timer.sh` y `check.sh` dentro de la workstation.

### 4.6 Qué hace el provisionado

| Etapa | VM | Qué hace |
|---|---|---|
| Red | todas | `eth0` NAT lo crea Vagrant; `eth1` host-only con IP fija. |
| `common` | todas | Hostname, contraseña de root (`radiowits`), SSH con root y contraseña (`/etc/ssh/sshd_config.d/00-rhcsa-lab.conf`), bloque en `/etc/hosts`, paquetes base y comprobación de red e internet. |
| `upload-*` | workstation | Sube los scripts que existan junto al `Vagrantfile`. |
| `workstation` | workstation | Instala EPEL y `sshpass`; clona el repo en `/root/rhcsa-test-paper3` y pisa los archivos con tus versiones locales; crea los atajos `exam-timer` y `rhcsa-check`; genera una clave SSH y la copia a `servera` y `serverb`; muestra una tabla de conectividad. |
| `env` | workstation | Ejecuta `env.sh`. Solo con `AUTO_ENV=1` o a demanda: `vagrant provision workstation --provision-with env`. |

### 4.7 Variables de entorno

| Variable | Valor por defecto | Efecto |
|---|---|---|
| `LAB_BOX` | `rockylinux/9` | Box a usar (por ejemplo `almalinux/9` si la de Rocky falla). |
| `LAB_ROOT_PASS` | `radiowits` | Contraseña de root. Debe coincidir con `ROOT_PASS` en `check.sh`. |
| `AUTO_ENV` | (vacío) | Con `1`, ejecuta `env.sh` al terminar el provisionado. |
| `SKIP_PREFLIGHT` | (vacío) | Con `1`, omite la verificación de `/etc/vbox/networks.conf`. |

### 4.8 Comandos del día a día

| Qué querés hacer | Comando |
|---|---|
| Ver el estado de las VMs | `vagrant status` |
| Guardar el punto de partida (antes de `env.sh`) | `vagrant snapshot save inicio` |
| Repetir el simulacro desde cero | `vagrant snapshot restore inicio` y luego `./env.sh` |
| Apagar el laboratorio | `vagrant halt` |
| Volver a encenderlo | `vagrant up` |
| Volver a ejecutar el provisionado de la workstation | `vagrant provision workstation` |
| Borrar todo | `vagrant destroy -f` |

### 4.9 Notas y límites

| Tema | Detalle |
|---|---|
| Discos extra | Usan la función `config.vm.disk` de Vagrant, que es **experimental** (el `Vagrantfile` activa `VAGRANT_EXPERIMENTAL=disks`). Verificá en serverb con `lsblk`. Si no aparecen, probá `VAGRANT_EXPERIMENTAL=disks vagrant up`. |
| Box de Rocky | La box oficial tuvo caídas puntuales (404) al salir nuevas versiones menores. Si pasa, usá `LAB_BOX=almalinux/9` u otra box compatible con VirtualBox. |
| Carpetas compartidas | Están desactivadas a propósito (los Guest Additions de la box de Rocky dieron problemas). Los archivos se suben con el provisioner `file`. |
| `env.sh` | Descarga y ejecuta scripts del repo **original** (`codexchangee`), no de tu fork. Revisalos antes (ver [5.6](#56-revisar-los-scripts-antes-de-ejecutarlos-importante)). |
| Hostname de servera | Queda como `servera`. `check.sh` (Q02) espera que lo cambies vos a `node1.example.com` durante el examen. |
| `content.example.com` / `classroom.example.com` | No se simulan: son tareas del examen (Q03, Q09, Q17). Ver [5.7](#57-opcional-simular-contentexamplecom-y-classroomexamplecom). |

---

## 5. Instalación manual paso a paso

### 5.1 Crear las tres VMs

1. Instalá el SO en las tres VMs (puede ser una instalación mínima + SSH).
2. Nombralas `workstation`, `servera` y `serverb`.
3. A **serverb** agregale los discos extra antes de arrancar (ver tabla de requisitos).
4. A cada VM dale **dos adaptadores de red**:

| Adaptador | Tipo | Para qué |
|---|---|---|
| 1 | Red interna / Host-only (`172.25.250.0/24`) | Comunicación entre las 3 VMs |
| 2 | NAT | Salida a internet |

### 5.2 Configurar la IP fija de cada máquina

Primero identificá el nombre de tu conexión y tu interfaz:

```bash
nmcli device status
nmcli connection show
```

Reemplazá `<CONEXION>` por el nombre de la conexión de la **red interna** y ejecutá en cada VM:

| VM | Comandos |
|---|---|
| workstation | `nmcli con mod "<CONEXION>" ipv4.method manual ipv4.addresses 172.25.250.9/24` |
| servera | `nmcli con mod "<CONEXION>" ipv4.method manual ipv4.addresses 172.25.250.10/24` |
| serverb | `nmcli con mod "<CONEXION>" ipv4.method manual ipv4.addresses 172.25.250.11/24` |

Luego en cada una:

```bash
nmcli con up "<CONEXION>"
ip -4 addr show
```

> ⚠️ **Q02** pide configurar la red del servidor. No resuelvas esa tarea de antemano: configurá
> solo lo mínimo para que las VMs se vean entre sí.

### 5.3 Nombres de host y `/etc/hosts`

En **cada VM**, agregá estas líneas a `/etc/hosts`:

```
172.25.250.9   workstation
172.25.250.10  servera node1.example.com node1
172.25.250.11  serverb node2.example.com node2
```

Y fijá el hostname de la workstation:

```bash
hostnamectl set-hostname workstation
```

> En servera **no** pongas todavía el hostname `node1.example.com`: `check.sh` (Q02) verifica
> justamente que lo hayas configurado vos durante el examen.

### 5.4 Acceso SSH como root

`check.sh` entra a los servidores con `root` y la contraseña **`radiowits`** (está escrita dentro
del script en `ROOT_PASS`).

**En servera y serverb**, como root:

```bash
echo 'root:radiowits' | chpasswd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd
```

> En RHEL 9 puede haber archivos extra en `/etc/ssh/sshd_config.d/` que pisan estas opciones.
> Si el login falla, revisá `grep -r PermitRootLogin /etc/ssh/`.

**En la workstation**, probá la conexión y copiá tu clave (así `env.sh` no te pide la contraseña):

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
ssh-copy-id root@servera
ssh-copy-id root@serverb
ssh root@servera hostname
ssh root@serverb hostname
```

> Si cambiás la contraseña de root, editá la variable `ROOT_PASS` al inicio de `check.sh`.
> **Q16** evalúa justamente que la contraseña de root de node2 siga siendo la correcta.

### 5.5 Clonar el repo en la workstation

```bash
sudo dnf install -y git curl
git clone https://github.com/tercemundo/rhcsa-test-paper3.git
cd rhcsa-test-paper3
chmod +x *.sh
```

### 5.6 Revisar los scripts antes de ejecutarlos (importante)

`env.sh` **no usa los archivos de tu clon**: descarga `workstation.sh`, `servera.sh` y `serverb.sh`
desde el repo original `codexchangee/rhcsa-test-paper3` y los ejecuta como root.

```bash
cat workstation.sh servera.sh serverb.sh
```

Si querés que use **tu fork**, cambiá las tres URLs al inicio de `env.sh`:

```bash
sed -i 's#codexchangee/rhcsa-test-paper3#tercemundo/rhcsa-test-paper3#g' env.sh
```

### 5.7 (Opcional) Simular `content.example.com` y `classroom.example.com`

Estos nombres existen solo en el aula oficial de Red Hat. Para que las tareas Q03, Q09 y Q17 sean
posibles en tu laboratorio, definí a qué apuntan.

| Nombre | Se usa en | Sugerencia para casa |
|---|---|---|
| `content.example.com` | Q03 y Q17 (repositorios dnf) | Apuntalo a un servidor web que sirva un espejo de BaseOS/AppStream (por ejemplo, la propia workstation con `httpd` y el ISO montado). |
| `classroom.example.com` | Q09 (NTP con chrony) | Apuntalo a un servidor NTP (por ejemplo, la workstation con `chronyd` como servidor). |

Ejemplo de entrada en `/etc/hosts` de las tres VMs (ajustá la IP a donde montes el servicio):

```
172.25.250.9  content.example.com classroom.example.com
```

> `check.sh` solo comprueba que el texto `content.example.com` aparezca en `/etc/yum.repos.d` y
> `classroom.example.com` en `/etc/chrony.conf`. No verifica que el repo realmente funcione.

### 5.8 Tomar un snapshot

Antes de ejecutar `env.sh`, hacé un **snapshot** de las tres VMs. Así podés repetir el simulacro
las veces que quieras volviendo a ese punto.

---

## 6. Cómo se usa (flujo del examen)

| Paso | Dónde | Comando | Qué pasa |
|---|---|---|---|
| 1 | workstation | `sudo ./env.sh` | Prepara workstation, servera y serverb (los dos últimos por SSH). |
| 2 | workstation | `sudo ./exam-timer.sh start 180` | Inicia el cronómetro de 3 horas. |
| 3 | workstation | abrir `html/` o el enunciado | Leés las consignas. ⚠️ Confirmar dónde está el enunciado. |
| 4 | servera / serverb | (a mano) | Resolvés las tareas conectándote por SSH. |
| 5 | otra terminal | `sudo ./exam-timer.sh live` | Mirás cuánto tiempo te queda. |
| 6 | workstation | `sudo ./exam-timer.sh finish` | Terminás antes de tiempo: corrige y muestra tu tiempo usado. |
| 7 | workstation | `sudo ./check.sh` | Alternativa: corregir sin timer. |

Ejemplo de la salida de `check.sh`:

```
Connecting to node1 (Q02–Q15)
 ✅ Q02 Hostname correct
 ❌ Q03 Repositories missing
 ...
Q     | Task                 | Result
------------------------------------------
Q02   | Network              | PASS
Q03   | Repo                 | FAIL
------------------------------------------
TOTAL: 14 / 20 → 70%
RESULT: PASS
```

Se aprueba con **70 % o más** (`PASS_THRESHOLD=70`).

---

## 7. Tareas que se evalúan

`check.sh` evalúa 20 tareas (Q02 a Q21). La **Q01** no se corrige automáticamente.

### En node1 (servera)

| Q | Tema | Qué verifica `check.sh` |
|---|---|---|
| Q02 | Red / hostname | El hostname es exactamente `node1.example.com`. |
| Q03 | Repositorios | Existe `content.example.com` en `/etc/yum.repos.d`. |
| Q04 | httpd + SELinux | `httpd` activo y algo escuchando en el puerto **82**. |
| Q05 | Usuarios y grupo | Existen el grupo `sysadm` y los usuarios `harry` y `natasha`. |
| Q06 | Directorio colaborativo | `/shared/sysadm` existe con permisos **2770** (SGID). |
| Q07 | Cron | `natasha` tiene un cron con `*/3` (cada 3 minutos). |
| Q08 | Backup | `/root/archive.gz` existe y es un archivo gzip. |
| Q09 | NTP | `/etc/chrony.conf` contiene `classroom.example.com`. |
| Q10 | `find` | Existe el directorio `/root/found`. |
| Q11 | `grep` | El archivo `/root/lines` existe y no está vacío. |
| Q12 | autofs | El servicio `autofs` está activo. |
| Q13 | UID | El usuario `John` existe con UID **1545**. |
| Q14 | Login script | `pandora` tiene un script ejecutable referenciado en `.bash_profile` que muestra "welcome to rhcsa examination". |
| Q15 | Contenedor | Usuario `siya`: imagen `codesxchange/watcher`, contenedor `watcher` corriendo y servicio systemd de usuario `container-watcher.service` habilitado y activo. |

### En node2 (serverb)

| Q | Tema | Qué verifica `check.sh` |
|---|---|---|
| Q16 | Contraseña de root | Se puede entrar por SSH como root con la contraseña de `ROOT_PASS`. |
| Q17 | Repositorios | Existe `content.example.com` en `/etc/yum.repos.d`. |
| Q18 | tuned | Hay un perfil de `tuned` activo. |
| Q19 | Swap | `swapon --show` muestra una swap cuyo tercer campo contiene un `7`. |
| Q20 | LVM | `/mnt/database` está montado. |
| Q21 | Resize | El tamaño de `/home` está entre **140 y 170 MB**. |

---

## 8. Timer de examen

El archivo `exam-timer.sh` agrega un cronómetro con avisos y corrección automática.
Funciona en la **workstation**, como root, y **no modifica** `check.sh`.

### Comandos

| Comando | Qué hace |
|---|---|
| `./exam-timer.sh start [min]` | Inicia el examen. Sin argumento dura **180 minutos** (3 horas, como el EX200 real). |
| `./exam-timer.sh status` | Muestra el tiempo restante una vez. |
| `./exam-timer.sh live` | Cuenta regresiva en vivo; conviene en una segunda terminal. |
| `./exam-timer.sh finish` | Terminás antes: ejecuta `check.sh` y muestra el tiempo usado. |
| `./exam-timer.sh stop` | Cancela el timer sin corregir. |

### Comportamiento

| Momento | Qué ocurre |
|---|---|
| 30, 10, 5 y 1 minuto antes del final | Aviso en pantalla con `wall` (solo los umbrales menores a la duración elegida). |
| Al agotarse el tiempo | Aviso final y ejecución automática de `check.sh`. |
| Resultado | Se guarda sin colores en `/root/resultado_examen.txt`. |
| Estado | Se guarda en `/root/.rhcsa_timer` y se borra al terminar. |

### Ejemplos

```bash
# Examen de 3 horas con corrección automática al final
sudo ./exam-timer.sh start

# Examen corto de 90 minutos
sudo ./exam-timer.sh start 90

# Desactivar la corrección automática al agotarse el tiempo
sudo AUTO_CHECK=no ./exam-timer.sh start 180

# Ver el tiempo en una segunda terminal
sudo ./exam-timer.sh live

# Mostrar el tiempo refrescado cada segundo con watch
sudo watch -n1 ./exam-timer.sh status
```

> Importante: `wall` solo avisa en las terminales **de la workstation**. Si estás conectado
> por SSH a servera o serverb, usá `live` en una terminal aparte para ver el tiempo.

### Alternativa mínima: poner el timer dentro de `check.sh`

Si preferís no usar un script aparte, podés medir el tiempo transcurrido en `check.sh`.
Al principio del script, después de `need_root`, agregá:

```bash
START_FILE="/root/.rhcsa_start"
[[ -f "$START_FILE" ]] || date +%s > "$START_FILE"
```

Y antes de la tabla final (`echo -e "\n${bold}${blue}Summary${reset}"`):

```bash
ELAPSED=$(( $(date +%s) - $(cat "$START_FILE") ))
printf "Tiempo transcurrido: %02d:%02d:%02d\n" $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60))
```

Para reiniciar la medición: `rm /root/.rhcsa_start`.

---

## 9. Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Permission denied (publickey,...)` al hacer SSH | Login de root por contraseña deshabilitado | Ver paso 5.4 y revisar `/etc/ssh/sshd_config.d/`. |
| `check.sh` marca todo ❌ de un nodo | No hay conexión SSH o la IP no coincide | `ping 172.25.250.10` y `ssh root@172.25.250.10`. |
| `Run as root` | Ejecutaste sin permisos | Usá `sudo` o entrá como root. |
| `sshpass: command not found` | Falta el paquete | `dnf install -y sshpass` (puede requerir EPEL en RHEL/Rocky/Alma). |
| `env.sh`: `Failed to download workstation script` | Sin internet o sin DNS | Revisá el adaptador NAT. |
| Q03/Q17 imposibles de resolver | No existe `content.example.com` | Ver paso 5.7. |
| Q09 imposible de resolver | No existe `classroom.example.com` | Ver paso 5.7. |
| Q15 falla al bajar la imagen | Sin internet en servera | Habilitá NAT en servera. |
| `exam-timer.sh`: `Ya hay un examen en curso` | Quedó un timer activo | `./exam-timer.sh stop`. |
| `vagrant up` aborta con el aviso de `networks.conf` | VirtualBox no autoriza `172.25.250.0/24` | Ver [4.3](#43-autorizar-la-red-host-only-solo-linux-y-macos). |
| `The IP address configured for the host-only network is not within the allowed ranges` | Igual que arriba | Ver [4.3](#43-autorizar-la-red-host-only-solo-linux-y-macos). |
| `bad interpreter` / `\r: command not found` en los `.sh` | Finales de línea CRLF (clon en Windows) | Copiá `.gitattributes` y volvé a clonar, o `sed -i 's/\r$//' *.sh`. |
| La workstation no puede entrar por SSH a servera/serverb | Los servidores no terminaron de arrancar | `vagrant provision workstation` (reintenta copiar las claves). |
| serverb no muestra los discos extra | Función de discos experimental | `VAGRANT_EXPERIMENTAL=disks vagrant up` y revisá `lsblk`. |
| No aparecen los avisos `wall` | Estás en otra máquina o sin TTY | Usá `live` en una terminal de la workstation. |

---

## 10. Advertencias de seguridad

| Riesgo | Detalle | Recomendación |
|---|---|---|
| Ejecución remota de código | `env.sh` descarga y ejecuta como root scripts desde GitHub (repo original, no el fork). | Leé los scripts primero y apuntá `env.sh` a tu fork si querés controlar su contenido. |
| Contraseñas en texto plano | `ROOT_PASS="radiowits"` y `sshpass -p` dejan la contraseña visible en el script y en la lista de procesos. | Usalo **solo en VMs de laboratorio**, nunca en equipos reales. |
| SSH root con contraseña | Se habilita para que funcione el corrector. | No lo expongas a internet; usá red interna. |
| `StrictHostKeyChecking=no` | Desactiva la verificación de claves de host. | Aceptable en laboratorio aislado. |

---

## 11. Limitaciones conocidas del corrector

| Tarea | Limitación |
|---|---|
| Q04 | `ss -tuln` con el puerto 82 más `systemctl is-active httpd`; no verifica explícitamente el contexto SELinux. |
| Q08 | Solo comprueba que el archivo sea gzip, no su contenido. Nota: el nombre es `archive.gz`. |
| Q10 y Q11 | Solo comprueban que exista el directorio o el archivo, no que el contenido sea correcto. |
| Q19 | Busca un `7` en la tercera columna de `swapon --show`; puede dar falsos positivos o negativos según el tamaño. |
| Q21 | Acepta cualquier tamaño de `/home` entre 140 y 170 MB. |
| General | `TOTAL=20` está fijo; si agregás o quitás tareas, ajustalo. |

---

## Créditos

Basado en el trabajo original de [`codexchangee`](https://github.com/codexchangee/rhcsa-test-paper3).
Esto es un recurso de práctica no oficial y no está afiliado a Red Hat. Red Hat y RHCSA son marcas
registradas de Red Hat, Inc.
