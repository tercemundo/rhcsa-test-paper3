# RHCSA Test Paper 3 – Simulacro de examen con autocorrección

Simulacro práctico del examen **RHCSA (EX200)** para practicar en tu propio laboratorio.
Un script prepara el escenario en las máquinas, vos resolvés las tareas a mano y otro script
(`check.sh`) **corrige automáticamente** y te da un porcentaje y un veredicto PASS/FAIL.

El laboratorio automatizado usa **AlmaLinux 10** (`almalinux/10`) en las tres VMs.

> **Rama `v2`:** esta versión migró el laboratorio desde AlmaLinux 9 a AlmaLinux 10 y
> requirió actualizar el entorno anfitrión, recompilar los módulos kernel de VirtualBox
> y adaptar el provisionado, los scripts de preparación y la interfaz web. El detalle
> de la migración y de los cambios está en [Cambios de la versión v2](#cambios-de-la-versión-v2).

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
12. [Cambios de la versión v2](#cambios-de-la-versión-v2)

---

## 1. Contenido del repositorio

| Archivo / carpeta | Se ejecuta en | Para qué sirve |
|---|---|---|
| `env.sh` | workstation | Prepara el escenario con los scripts locales `workstation.sh`, `servera.sh` y `serverb.sh` (estos últimos se ejecutan en los servidores por SSH). |
| `verificar-escenario.sh` | workstation | Comprueba en modo de solo lectura que el escenario quedó preparado correctamente. |
| `workstation.sh` | workstation (lo lanza `env.sh`) | Prepara la máquina de control. ⚠️ Verificar contenido. |
| `servera.sh` | servera (lo lanza `env.sh` por SSH) | Deja servera en el estado inicial del examen. ⚠️ Verificar contenido. |
| `serverb.sh` | serverb (lo lanza `env.sh` por SSH) | Deja serverb en el estado inicial del examen. ⚠️ Verificar contenido. |
| `check.sh` | workstation | **Corrector**: se conecta a node1 y node2 por SSH, evalúa 20 tareas y muestra el resultado. |
| `paper-check.sh` | workstation | ⚠️ Verificar. Por el nombre, probablemente complementa la corrección o el enunciado. |
| `html/` | tu navegador | Enunciado del examen en versión web, con tema claro/oscuro. |
| `exam-timer.sh` | workstation | **Nuevo**: cuenta regresiva con avisos y autocorrección (ver [sección 8](#8-timer-de-examen)). |
| `Vagrantfile` | tu PC | **Nuevo**: levanta las 3 VMs de AlmaLinux 10 en VirtualBox con NAT + host-only (ver [sección 4](#4-instalación-automatizada-con-vagrant-recomendada)). |
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

### Acceso al examen desde el navegador del host

El examen se publica con `httpd` en la workstation:

```
http://172.25.250.9/
```

> ⚠️ Si el navegador dice **"no se puede acceder a este sitio"**, es el `firewalld` de la workstation:
> la zona `public` no traía el servicio `http` permitido y el firewall rechazaba las conexiones
> (por eso el puerto respondía *No route to host*). Los scripts ya lo abren de forma **permanente**
> (`firewall-cmd --permanent --add-service=http`), así que un `vagrant up`/`env.sh` futuro no lo rompe.
> Para revisarlo a mano:
>
> ```bash
> vagrant ssh workstation -c "sudo firewall-cmd --list-services"
> # debe incluir: http
> ```

---

## 3. Requisitos

### Sistema operativo

| Máquina | SO recomendado | Motivo |
|---|---|---|
| workstation | AlmaLinux 10 (recomendado), RHEL 10 o compatible (también Fedora reciente) | Los scripts usan `dnf` para instalar `sshpass` (EPEL 10). |
| servera / serverb | AlmaLinux 10 (recomendado), RHEL 10 o compatible | Las tareas incluyen `dnf5`, SELinux, `firewalld`, `tuned`, `podman`, LVM y `autofs`. |

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
| `curl` | Descargas y verificaciones de red | `dnf install -y curl` |
| `git` | Clonar este repo | `dnf install -y git` |

### Red e internet

| Necesidad | Detalle |
|---|---|
| Subred | Las tres VMs deben estar en `172.25.250.0/24` (red interna o host-only). |
| Internet | Hace falta para instalar paquetes, clonar el repositorio y para la tarea Q15 (descargar la imagen `codesxchange/watcher` con Podman). Agregá un segundo adaptador NAT. |
| Nombres del laboratorio de Red Hat | Q03/Q17 buscan `content.example.com` en `/etc/yum.repos.d` y Q09 busca `classroom.example.com` en `/etc/chrony.conf`. Fuera del aula oficial hay que simularlos (ver paso 5.7). |

---

## 4. Instalación automatizada con Vagrant (recomendada)

Con un solo `vagrant up` se crean **3 VMs de VirtualBox**, cada una con **dos interfaces de red**
(NAT para internet + host-only para verse entre ellas), con root/SSH configurados, `/etc/hosts`
completo y la workstation lista con el corrector y el timer. La box base es la oficial
`almalinux/10` del catálogo de AlmaLinux. Si preferís hacerlo a mano, saltá a la
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
| VirtualBox | **7.2.10 o superior** (obligatorio). La versión validada en este laboratorio fue **7.2.22r175245**. Las versiones anteriores no exponen AVX2/BMI2 al guest y AlmaLinux 10 aborta el arranque con `Fatal glibc error: CPU does not support x86-64-v3` ([VirtualBox#642](https://github.com/VirtualBox/virtualbox/issues/642)). Instalalo desde el catálogo oficial de Oracle: <https://download.virtualbox.org/virtualbox/>. En Debian/Ubuntu/Zorin usá el `.deb` de la serie 7.2 de tu distro (noble para Ubuntu 24.04). |
| Vagrant | 2.3.4 o superior. Con VirtualBox 7.2 necesitás Vagrant 2.4.x (incorpora el driver `Version_7_2`); la versión validada fue **2.4.9**. |
| Arquitectura | x86_64 (Intel/AMD). No sirve en Mac con Apple Silicon. |
| RAM libre | Unos 6 GB para las 3 VMs. |
| Disco libre | Unos 25–30 GB. |
| Internet | Para bajar la box (`almalinux/10`), los paquetes y el repo. |
| Secure Boot | Opcional: si está activo, el módulo `vboxdrv` debe estar firmado. |

### 4.3 Actualizar VirtualBox y recompilar sus módulos kernel

Para ejecutar AlmaLinux 10 se reemplazó el VirtualBox 7.0 que entregaba la distribución
por **VirtualBox 7.2** de Oracle. En el host de desarrollo se validó la versión
**7.2.22r175245**, instalada desde el paquete `.deb` para Ubuntu Noble:

```bash
# 1. Retirar el VirtualBox provisto por Zorin/Ubuntu.
sudo apt purge -y virtualbox virtualbox-qt virtualbox-dkms

# 2. Instalar el paquete oficial de Oracle (ajustá el nombre a la versión descargada).
sudo apt install -y ./virtualbox-7.2_7.2.22-175245~Ubuntu~noble_amd64.deb

# 3. Instalar los headers del kernel que está en uso.
sudo apt install -y "linux-headers-$(uname -r)"

# 4. Recompilar y cargar los módulos kernel de VirtualBox.
sudo /usr/lib/virtualbox/vboxdrv.sh
sudo modprobe vboxdrv
```

> En este entorno se recompilaron `vboxdrv`, `vboxnetflt` y `vboxnetadp` contra el kernel
> `6.17.0-22-generic`. Si cambia el kernel o se actualiza VirtualBox, hay que repetir
> este paso; de lo contrario `vboxdrv` puede quedar con un `vermagic` incompatible.

Comprobación rápida:

```bash
VBoxManage --version
modinfo vboxdrv | grep -E '^(version|vermagic):'
lsmod | grep '^vbox'
```

La instalación desde el repositorio de la distribución no alcanza para este laboratorio:
la versión 7.0 disponible en Zorin no cumple los requisitos de CPU de AlmaLinux 10.

### 4.4 Autorizar la red host-only (solo Linux y macOS)

VirtualBox solo permite redes host-only dentro de `192.168.56.0/21` salvo que autorices otro rango.
Hacelo una sola vez (en Windows no hace falta):

```bash
sudo mkdir -p /etc/vbox
echo '* 172.25.250.0/24' | sudo tee -a /etc/vbox/networks.conf
```

El `Vagrantfile` verifica esto antes de `vagrant up` y, si falta, se detiene con este mismo aviso.

### 4.5 Archivos a copiar al repo

Copiá estos archivos a la **raíz** de tu clon (junto a `check.sh`, `env.sh`, etc.):

| Archivo | Para qué sirve |
|---|---|
| `Vagrantfile` | Define las 3 VMs, sus redes, discos y provisionado. |
| `vagrant/provision-common.sh` | Se ejecuta en las 3 VMs: hostname, root/SSH, `/etc/hosts`, SELinux, red IPv4-only, paquetes base, verificación de red. |
| `vagrant/provision-workstation.sh` | Solo workstation: sshpass, repo, atajos, claves SSH, motd. |
| `exam-timer.sh` | El timer (se copia a la workstation). |
| `verificar-escenario.sh` | Verificación de solo lectura del escenario (no corrige el examen). |
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

### 4.6 Levantar el laboratorio

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

### 4.7 Qué hace el provisionado

| Etapa | VM | Qué hace |
|---|---|---|
| Red | todas | `eth0` NAT lo crea Vagrant; `eth1` host-only con IP fija. |
| `common` | todas | Hostname, contraseña de root (`radiowits`), SSH con root y contraseña (`/etc/ssh/sshd_config.d/00-rhcsa-lab.conf`), bloque en `/etc/hosts`, paquetes base y comprobación de red e internet. |
| `upload-*` | workstation | Sube los scripts que existan junto al `Vagrantfile`. |
| `workstation` | workstation | Instala EPEL y `sshpass`; clona el repo en `/root/rhcsa-test-paper3` y pisa los archivos con tus versiones locales; crea los atajos `exam-timer` y `rhcsa-check`; genera una clave SSH y la copia a `servera` y `serverb`; muestra una tabla de conectividad. |
| `env` | workstation | Ejecuta `env.sh`. Solo con `AUTO_ENV=1` o a demanda: `vagrant provision workstation --provision-with env`. |

### 4.8 Variables de entorno

| Variable | Valor por defecto | Efecto |
|---|---|---|
| `LAB_BOX` | `almalinux/10` | Box a usar. El proyecto está preparado para AlmaLinux 10. |
| `LAB_BOX_SERVER_URL` | `https://vagrant.almalinux.org` | Catálogo oficial de boxes de AlmaLinux. |
| `LAB_BOX_VERSION` | (última) | Fija una versión concreta de la box (por ejemplo `10.2.20261109`). |
| `LAB_ROOT_PASS` | `radiowits` | Contraseña de root. Debe coincidir con `ROOT_PASS` en `check.sh`. |
| `AUTO_ENV` | (vacío) | Con `1`, ejecuta `env.sh` al terminar el provisionado. |
| `SKIP_PREFLIGHT` | (vacío) | Con `1`, omite la verificación de `/etc/vbox/networks.conf`. |

### 4.9 Comandos del día a día

| Qué querés hacer | Comando |
|---|---|
| Ver el estado de las VMs | `vagrant status` |
| Guardar el punto de partida (antes de `env.sh`) | `vagrant snapshot save inicio` |
| Repetir el simulacro desde cero | `vagrant snapshot restore inicio` y luego `./env.sh` |
| Apagar el laboratorio | `vagrant halt` |
| Volver a encenderlo | `vagrant up` |
| Volver a ejecutar el provisionado de la workstation | `vagrant provision workstation` |
| Borrar todo | `vagrant destroy -f` |

### 4.10 Notas y límites

| Tema | Detalle |
|---|---|
| Discos extra | Usan la función `config.vm.disk` de Vagrant, que es **experimental** (el `Vagrantfile` activa `VAGRANT_EXPERIMENTAL=disks`). Verificá en serverb con `lsblk`. Si no aparecen, probá `VAGRANT_EXPERIMENTAL=disks vagrant up`. |
| Catálogo de boxes | AlmaLinux movió sus boxes a `https://vagrant.almalinux.org` porque HCP Vagrant Cloud se retira el 31/12/2026. El `Vagrantfile` ya apunta allí con `config.vm.box_server_url`; podés cambiarlo con `LAB_BOX_SERVER_URL`. |
| Carpetas compartidas | Están desactivadas a propósito (evitan problemas de Guest Additions y permisos entre providers). Los archivos se suben con el provisioner `file`. |
| `env.sh` | Usa los scripts locales `workstation.sh`, `servera.sh` y `serverb.sh`; `workstation.sh` los copia y ejecuta por SSH en los servidores. Revisalos antes (ver [5.6](#56-revisar-los-scripts-antes-de-ejecutarlos-importante)). |
| Hostname de servera | Queda como `servera`. `check.sh` (Q02) espera que lo cambies vos a `node1.example.com` durante el examen. |
| `content.example.com` / `classroom.example.com` | No se simulan: son tareas del examen (Q03, Q09, Q17). Ver [5.7](#57-opcional-simular-contentexamplecom-y-classroomexamplecom). |

### 4.11 Migrar un laboratorio existente a AlmaLinux 10

El cambio de box no se aplica a VMs ya creadas: hay que destruirlas y volver a levantarlas.
**Esto borra el contenido de las VMs**; si tenés algo que conservar, hacé antes un snapshot o copiá los archivos.

```bash
# Desde la raíz del repo
vagrant destroy -f

# Opcional: borrar la box vieja de AlmaLinux 9 (ya no se usa)
vagrant box remove almalinux/9 --provider virtualbox 2>/dev/null || true

# Crear las 3 VMs con AlmaLinux 10
vagrant up
```

El `Vagrantfile` usa `almalinux/10` y el catálogo `https://vagrant.almalinux.org`. Si tu Vagrant es
viejo y no encuentra la box, actualizalo o ejecutá:

```bash
export VAGRANT_SERVER_URL=https://vagrant.almalinux.org
vagrant up
```

> Si además tenés un proyecto propio de boxes, regenerá esa box con AlmaLinux 10 y apuntá
> `LAB_BOX` al nombre de tu box (por ejemplo `mi-lab/almalinux-10`).

### 4.12 Diseño de red del laboratorio (100% IPv4)

| Interfaz | Red | Uso | Ruta por defecto |
|---|---|---|---|
| `eth0` (NAT) | `10.0.2.0/24` | Salida a internet, `dnf`, `git clone` | **Sí** (gateway `10.0.2.2`) |
| `eth1` (host-only) | `172.25.250.0/24` | Comunicación **entre VMs** (servera ↔ serverb ↔ workstation) | **No** |

El aprovisionamiento (`vagrant/provision-common.sh`) deja las VMs así:

- **Internet siempre por el NAT.** Vagrant escribe `GATEWAY=172.25.250.1` en la interfaz host-only
  (plantilla `network_static.erb` de los guests RedHat), y esa ruta compite con la del NAT y se queda
  con todo el tráfico de salida: `dnf` y `curl` se quedan sin internet aunque el NAT esté perfecto.
  El script le saca el gateway a la host-only y le pone `ipv4.never-default=yes`.
- **IPv6 deshabilitado** (`net.ipv6.conf.*.disable_ipv6=1` + `ipv6.method=disabled` en NetworkManager).
  El NAT de VirtualBox no tiene IPv6 y los resolvers devolvían registros AAAA inalcanzables.
- **DNS fijo en `8.8.8.8` y `1.1.1.1`**, configurado en el perfil de NetworkManager del NAT y escrito
  en `/etc/resolv.conf`.
- **SELinux deshabilitado** (`setenforce 0`, `SELINUX=disabled` en `/etc/selinux/config` y
  `selinux=0` en el cmdline de grub). Motivo: Vagrant escribe el perfil de red
  `eth1.nmconnection` con contexto SELinux `user_tmp_t`; con SELinux en enforcing, NetworkManager no
  puede renombrar ese archivo, `nmcli` falla y la corrección de red de arriba no se puede aplicar.

> ⚠️ **La pregunta 4 del examen es sobre SELinux** (`semanage port -a -t http_port_t -p tcp 82`).
> Con SELinux deshabilitado, `semanage` no funciona y esa pregunta no se puede resolver. Si preferís
> conservar el ejercicio, en `vagrant/provision-common.sh` cambiá `SELINUX=disabled` por
> `SELINUX=permissive` (el `restorecon` del perfil NM ya está, así que `nmcli` sigue funcionando).

Verificación rápida en cualquier VM:

```bash
ip -4 route show default      # default via 10.0.2.2 dev eth0
ip route show 172.25.250.0/24 # red host-only, sin default
cat /etc/resolv.conf          # nameserver 8.8.8.8 / 1.1.1.1
ping -c1 8.8.8.8              # OK
```

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

> En RHEL/AlmaLinux 9 y 10 puede haber archivos extra en `/etc/ssh/sshd_config.d/` que pisan estas opciones.
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

`env.sh` usa los scripts locales del clon y los ejecuta como root. `workstation.sh` copia
`servera.sh` y `serverb.sh` a los servidores y los lanza por SSH:

```bash
cat env.sh workstation.sh servera.sh serverb.sh
```

Estos scripts modifican el estado inicial de las VMs (paquetes, usuarios, LVM, servicios y
hostname). Revisalos antes de ejecutarlos.

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
| 1b | workstation | `sudo ./verificar-escenario.sh` | **Opcional**: comprueba (sin modificar nada) que el escenario quedó armado bien. |
| 2 | workstation | `sudo ./exam-timer.sh start 180` | Inicia el cronómetro de 3 horas. |
| 3 | workstation | abrir `html/` o el enunciado | Leés las consignas. ⚠️ Confirmar dónde está el enunciado. |
| 4 | servera / serverb | (a mano) | Resolvés las tareas conectándote por SSH. |
| 5 | otra terminal | `sudo ./exam-timer.sh live` | Mirás cuánto tiempo te queda. |
| 6 | workstation | `sudo ./exam-timer.sh finish` | Terminás antes de tiempo: corrige y muestra tu tiempo usado. |
| 7 | workstation | `sudo ./check.sh` | Alternativa: corregir sin timer. |

### 6.1 Verificar que el escenario quedó armado

`verificar-escenario.sh` es un chequeo **de solo lectura** (no corrige el examen ni toca nada).
Sirve para confirmar que `env.sh` dejó las VMs en el estado inicial esperado:

```bash
# En la workstation, como root
cd /root/rhcsa-test-paper3
./verificar-escenario.sh
```

Comprueba, entre otras cosas:

| VM | Qué verifica |
|---|---|
| Conectividad | ping y SSH root a `172.25.250.10` y `.11` |
| **servera** | hostname `machine1.exam.com`, `bzip2` desinstalado, httpd en el puerto **82**, `file1..file3` en `/var/www/html`, usuarios `remoteuser3`/`siya`/`simone`/`pandora` |
| **serverb** | hostname `machine2.exam.com`, password de root reseteada, VG `myvg` + LV `home`, `/home` montado desde el LV, entrada en `/etc/fstab`, `tuned` activo con perfil `balanced` |
| **workstation** | repo del lab, `exam-timer` y `rhcsa-check` enlazados, httpd activo, examen publicado (index + 20 preguntas + tema oscuro), export NFS, `sshpass` y llaves SSH, **firewalld con `http` permitido** (acceso desde el host a `http://172.25.250.9`) |

Sale con código 0 si todo está OK y 1 si algo falta.

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
| `sshpass: command not found` | Falta el paquete | `dnf install -y epel-release && dnf install -y sshpass` (EPEL 10 en RHEL/AlmaLinux 10). |
| `env.sh` no encuentra `workstation.sh` | El clon está incompleto o se ejecutó desde otro directorio | Verificá que `workstation.sh` esté junto a `env.sh` y ejecutalo desde la raíz del repo. |
| Q03/Q17 imposibles de resolver | No existe `content.example.com` | Ver paso 5.7. |
| Q09 imposible de resolver | No existe `classroom.example.com` | Ver paso 5.7. |
| Q15 falla al bajar la imagen | Sin internet en servera | Habilitá NAT en servera. |
| `exam-timer.sh`: `Ya hay un examen en curso` | Quedó un timer activo | `./exam-timer.sh stop`. |
| `vagrant up` aborta con el aviso de `networks.conf` | VirtualBox no autoriza `172.25.250.0/24` | Ver [4.4](#44-autorizar-la-red-host-only-solo-linux-y-macos). |
| `The IP address configured for the host-only network is not within the allowed ranges` | Igual que arriba | Ver [4.4](#44-autorizar-la-red-host-only-solo-linux-y-macos). |
| `bad interpreter` / `\r: command not found` en los `.sh` | Finales de línea CRLF (clon en Windows) | Copiá `.gitattributes` y volvé a clonar, o `sed -i 's/\r$//' *.sh`. |
| La workstation no puede entrar por SSH a servera/serverb | Los servidores no terminaron de arrancar | `vagrant provision workstation` (reintenta copiar las claves). |
| serverb no muestra los discos extra | Función de discos experimental | `VAGRANT_EXPERIMENTAL=disks vagrant up` y revisá `lsblk`. |
| No aparecen los avisos `wall` | Estás en otra máquina o sin TTY | Usá `live` en una terminal de la workstation. |

---

## 10. Advertencias de seguridad

| Riesgo | Detalle | Recomendación |
|---|---|---|
| Ejecución remota de código | `env.sh` ejecuta scripts locales como root y `workstation.sh` los copia y ejecuta por SSH en los servidores. | Revisá `env.sh`, `workstation.sh`, `servera.sh` y `serverb.sh` antes de ejecutarlos. |
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

## Cambios de la versión v2

La rama `v2` migra el laboratorio de AlmaLinux 9 a **AlmaLinux 10** y corrige problemas
detectados al levantar y usar las tres máquinas.

### Entorno y VirtualBox

- Se reemplazó el VirtualBox 7.0 de la distribución por **Oracle VirtualBox 7.2**; la versión
  validada fue **7.2.22r175245**, porque las versiones anteriores no exponen al guest las
  instrucciones de CPU necesarias para AlmaLinux 10.
- Se instalaron los headers del kernel en uso y se recompilaron los módulos kernel de
  VirtualBox (`vboxdrv`, `vboxnetflt` y `vboxnetadp`) para que coincidieran con el
  `vermagic` del kernel activo.
- Se validó el laboratorio con **Vagrant 2.4.9** y la box oficial `almalinux/10`, publicada
  en `https://vagrant.almalinux.org`.
- Se documentaron los pasos de actualización y recompilación en
  [4.3 Actualizar VirtualBox y recompilar sus módulos kernel](#43-actualizar-virtualbox-y-recompilar-sus-módulos-kernel).

### Provisionado y scripts

- `Vagrantfile` usa AlmaLinux 10, permite fijar la URL y la versión de la box, autoriza la
  red host-only `172.25.250.0/24` y sube a la workstation los scripts y recursos web locales.
- `vagrant/provision-common.sh` deja la red en modo IPv4-only: NAT como ruta predeterminada,
  host-only sin gateway, IPv6 deshabilitado y DNS público fijo.
- Se corrigieron los contextos SELinux de los perfiles de NetworkManager y se desactivó
  SELinux para que `nmcli` pueda reconfigurar las interfaces en el laboratorio.
- Se instalaron los paquetes requeridos para LVM y `semanage`, y se agregó EPEL 10 como
  respaldo para instalar `sshpass`.
- `servera.sh` y `serverb.sh` se adaptaron a `dnf5`, al hostname del escenario y a la
  detección de discos disponibles en VirtualBox.
- `serverb.sh` copia `/home` antes de montar el LV para no ocultar `/home/vagrant` y deja
  `/etc/fstab` intacto si la preparación del LVM falla.
- `env.sh` dejó de descargar scripts remotos y usa las versiones locales.
- `workstation.sh` publica también CSS y JavaScript, habilita HTTP en `firewalld` de forma
  permanente y mantiene la exportación NFS.

### Corrección, validación e interfaz

- `check.sh` reconoce EPEL 10 y ofrece una instalación de respaldo de `sshpass`.
- Se agregó `verificar-escenario.sh`, una comprobación de solo lectura del estado inicial de
  las tres VMs.
- Se agregó un tema claro/oscuro (`html/theme.css` y `html/theme.js`) y se integró en las
  páginas del examen.
- Se habilitó el acceso web al enunciado en `http://172.25.250.9/`.

### Compatibilidad y limitaciones

- La versión actual del proyecto está validada para **VirtualBox 7.2.22r175245**,
  **Vagrant 2.4.9** y **AlmaLinux 10**.
- Las VMs existentes de AlmaLinux 9 no se actualizan en sitio: hay que destruirlas y crear
  nuevamente el laboratorio.
- Desactivar SELinux permite estabilizar NetworkManager, pero impide usar `semanage`; por eso
  la pregunta sobre SELinux requiere usar `SELINUX=permissive` o resolverla en otro momento.

---

## Créditos

Basado en el trabajo original de [`codexchangee`](https://github.com/codexchangee/rhcsa-test-paper3).
Esto es un recurso de práctica no oficial y no está afiliado a Red Hat. Red Hat y RHCSA son marcas
registradas de Red Hat, Inc.
