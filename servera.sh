#!/bin/bash
#
# servera.sh (node1) - Escenario de las tareas Q02-Q15.
# Version para Vagrant/VirtualBox. Cambios respecto al original:
#   - NO reinicia (REBOOT=1 para reiniciar)
#   - NO instala "Server with GUI" (INSTALL_GUI=1 para instalarlo)
#   - NO pasa las interfaces a DHCP (podia dejar eth1 sin la IP 172.25.250.10)

INSTALL_GUI="${INSTALL_GUI:-0}"
REBOOT="${REBOOT:-0}"

current_hostname=$(hostname)
new_hostname="machine1.exam.com"

if [ "$current_hostname" != "$new_hostname" ]; then
    echo "Changing hostname from $current_hostname to $new_hostname"
    hostnamectl set-hostname "$new_hostname"
    sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts
else
    echo "Hostname is already $new_hostname"
fi

echo "Setting root password..."
echo "root:radiowits" | chpasswd

# Quitar bzip2 (parte del escenario)
yum remove -y bzip2 || true

echo "Installing httpd..."
yum install -y httpd
systemctl start httpd
systemctl enable httpd

CONF_FILE="/etc/httpd/conf/httpd.conf"
BACKUP_FILE="/etc/httpd/conf/httpd.conf.bak"
cp "$CONF_FILE" "$BACKUP_FILE"

echo "Updating Listen directives from port 80 to 82..."
grep -rl "Listen 80" /etc/httpd | xargs -r sed -i 's/Listen 80/Listen 82/g'

echo "Restarting httpd service..."
systemctl restart httpd
if systemctl is-active --quiet httpd; then
    echo "Port successfully changed to 82."
else
    echo "httpd failed. Reverting config..."
    cp "$BACKUP_FILE" "$CONF_FILE"
    systemctl restart httpd
fi

echo "Creating files in /var/www/html..."
mkdir -p /var/www/html
for f in file1 file2 file3; do
    printf "Welcome to RHCSA Examination\n" > /var/www/html/$f
done
chcon -t user_home_t /var/www/html/file1 || true

echo "Creating specified users..."
for username in remoteuser3 siya simone pandora; do
    id "$username" &>/dev/null || useradd "$username"
    echo "$username:radiowits" | chpasswd
done

if [ "$INSTALL_GUI" = "1" ] && ! rpm -qa | grep -q "gnome-session"; then
    echo "Installing Server with GUI..."
    dnf groupinstall -y "Server with GUI" || true
fi

echo "Script completed successfully."
history -c || true
rm -- "$0" || true

if [ "$REBOOT" = "1" ]; then
    echo "Rebooting system..."
    reboot
fi
