#!/bin/bash
#
# serverb.sh (node2) - Escenario de las tareas Q16-Q21.
# Version para Vagrant/VirtualBox. Cambios respecto al original:
#   - Detecta el disco extra libre (/dev/sdb en VirtualBox) en vez de fijar /dev/vdb
#   - Copia /home al nuevo LV ANTES de montarlo (si no, se oculta /home/vagrant
#     y vagrant ssh deja de funcionar)
#   - La linea de /etc/fstab solo se agrega si todo salio bien, y con nofail
#   - NO reinicia (REBOOT=1 para reiniciar) y NO instala la GUI (INSTALL_GUI=1)

INSTALL_GUI="${INSTALL_GUI:-0}"
REBOOT="${REBOOT:-0}"

warn(){ echo "[serverb] ADVERTENCIA: $*" >&2; }

current_hostname=$(hostname)
new_hostname="machine2.exam.com"
if [ "$current_hostname" != "$new_hostname" ]; then
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
fi

echo "root:password" | chpasswd

if [ "$INSTALL_GUI" = "1" ] && ! rpm -qa | grep -q "gnome-session"; then
    dnf groupinstall "Server with GUI" -y || true
fi

# ---------------------------------------------------------------------------
# Primer disco extra sin particiones, sin filesystem y sin montar
# ---------------------------------------------------------------------------
find_free_disk() {
    local d
    for d in $(lsblk -dnpo NAME,TYPE | awk '$2=="disk"{print $1}'); do
        if [ "$(lsblk -nro NAME "$d" | wc -l)" -eq 1 ] && ! blkid "$d" >/dev/null 2>&1; then
            echo "$d"; return 0
        fi
    done
    return 1
}

setup_home_lv() {
    local disk="$1" part
    printf 'o\nn\np\n1\n\n+200M\nw\n' | fdisk "$disk" || return 1
    partprobe "$disk"; udevadm settle
    part=$(lsblk -nlpo NAME "$disk" | sed -n 2p)
    [ -b "$part" ] || return 1

    pvcreate "$part"                      || return 1
    vgcreate myvg "$part"                 || return 1
    lvcreate -L 100M -n home myvg         || return 1
    mkfs.ext4 /dev/myvg/home              || return 1

    # Copiar el /home actual (incluye /home/vagrant) antes de montar encima
    mkdir -p /mnt/newhome
    mount /dev/myvg/home /mnt/newhome     || return 1
    cp -a /home/. /mnt/newhome/           || { umount /mnt/newhome; return 1; }
    umount /mnt/newhome
    mount /dev/myvg/home /home            || return 1
    restorecon -R /home 2>/dev/null || true

    grep -q '^/dev/myvg/home' /etc/fstab \
        || echo "/dev/myvg/home /home ext4 defaults,nofail 0 0" >> /etc/fstab
    return 0
}

if lvs myvg/home >/dev/null 2>&1; then
    echo "[serverb] myvg/home ya existe; se omite la parte de LVM."
else
    DISK="${DISK:-$(find_free_disk)}"
    if [ -z "${DISK:-}" ]; then
        warn "No hay disco extra libre; se omite la parte de LVM (fstab intacto)."
    else
        echo "[serverb] Usando disco $DISK para el LV de /home"
        setup_home_lv "$DISK" || warn "Fallo la preparacion de /home en LVM; revisa a mano (fstab NO se modifico si fallo antes del montaje)."
    fi
fi

# tuned (Q18)
command -v tuned-adm >/dev/null 2>&1 || dnf install -y tuned || true
systemctl enable --now tuned 2>/dev/null || true
tuned-adm profile balanced || true

# Preparacion para el reseteo de root (Q16)
dnf reinstall kernel-core -y || true
dracut -f --regenerate-all || true
grub2-mkconfig -o /boot/grub2/grub.cfg || true

history -c
rm -- "$0"

if [ "$REBOOT" = "1" ]; then
    reboot
fi
