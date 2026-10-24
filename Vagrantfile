# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Laboratorio RHCSA (rhcsa-test-paper3) en 3 VMs de VirtualBox
#
#   workstation  172.25.250.9    corrector + exam-timer.sh      (se levanta al final)
#   servera      172.25.250.10   "node1" en check.sh
#   serverb      172.25.250.11   "node2" en check.sh
#
# Cada VM tiene DOS interfaces:
#   eth0 = NAT        (salida a internet, la crea Vagrant)
#   eth1 = host-only  (red 172.25.250.0/24 entre las VMs y tu PC)
#
# Uso rapido:
#   vagrant up                 # levanta y provisiona las 3 VMs
#   vagrant ssh                # entra a la workstation (maquina primaria)
#   AUTO_ENV=1 vagrant up      # ademas ejecuta env.sh al final
#
# Variables de entorno opcionales:
#   LAB_BOX=almalinux/9        Otra box (por defecto rockylinux/9)
#   LAB_ROOT_PASS=radiowits    Password de root (debe coincidir con ROOT_PASS de check.sh)
#   AUTO_ENV=1                 Ejecuta env.sh automaticamente al terminar el provisionado
#   SKIP_PREFLIGHT=1           Omite la verificacion de /etc/vbox/networks.conf

Vagrant.require_version ">= 2.3.4"

# Los discos extra (config.vm.disk) son una funcion experimental de Vagrant
ENV["VAGRANT_EXPERIMENTAL"] ||= "disks"

BOX       = ENV.fetch("LAB_BOX", "almalinux/9")
ROOT_PASS = ENV.fetch("LAB_ROOT_PASS", "radiowits")
AUTO_ENV  = ENV["AUTO_ENV"] == "1"
SUBNET    = "172.25.250"

# Orden importante: la workstation va ultima porque en su provisionado
# copia su clave SSH a servera y serverb (que ya deben estar encendidos).
# disks = tamanos (en GB) de los discos extra sin usar. Ajustalos segun
# lo que pidan servera.sh / serverb.sh.
NODES = [
  { name: "servera",     ip: "#{SUBNET}.10", cpus: 1, memory: 2048, disks: [2] },
  { name: "serverb",     ip: "#{SUBNET}.11", cpus: 1, memory: 2048, disks: [5, 5] },
  { name: "workstation", ip: "#{SUBNET}.9",  cpus: 1, memory: 1536, disks: [] },
].freeze

# Archivos del repo que se copian a la workstation si existen junto al Vagrantfile.
# El resto del repo (por ejemplo la carpeta html/) se obtiene con git clone.
UPLOADS = %w[
  exam-timer.sh check.sh env.sh paper-check.sh
  workstation.sh servera.sh serverb.sh
].freeze

# ---------------------------------------------------------------------------
# Verificacion previa: VirtualBox 6.1.28+ en Linux/macOS solo permite redes
# host-only dentro de 192.168.56.0/21 salvo que se autorice otro rango.
# ---------------------------------------------------------------------------
if ARGV.include?("up") && ENV["SKIP_PREFLIGHT"] != "1" && !Vagrant::Util::Platform.windows?
  conf = "/etc/vbox/networks.conf"
  allowed = File.exist?(conf) &&
            File.readlines(conf).reject { |l| l.strip.start_with?("#") }
                .any? { |l| l.include?("172.25.") || l.include?("0.0.0.0/0") }
  unless allowed
    abort <<~MSG

      [LAB] VirtualBox no tiene autorizado el rango #{SUBNET}.0/24 para redes host-only.

      Solucion (una sola vez, como root):
        sudo mkdir -p /etc/vbox
        echo '* #{SUBNET}.0/24' | sudo tee -a /etc/vbox/networks.conf

      Despues volve a ejecutar:  vagrant up
      (Para omitir esta verificacion: SKIP_PREFLIGHT=1 vagrant up)

    MSG
  end
end

Vagrant.configure("2") do |config|
  config.vm.box = BOX
  config.vm.box_check_update = false
  config.vm.boot_timeout = 600

  # La box oficial de Rocky tuvo problemas con los Guest Additions / carpetas
  # compartidas, asi que no las usamos: los archivos se suben con el provisioner "file".
  config.vm.synced_folder ".", "/vagrant", disabled: true

  NODES.each do |n|
    config.vm.define n[:name], primary: (n[:name] == "workstation") do |node|
      node.vm.hostname = n[:name]

      # eth1: red host-only con IP fija (eth0 = NAT lo agrega Vagrant solo)
      node.vm.network "private_network", ip: n[:ip]

      n[:disks].each_with_index do |gb, i|
        node.vm.disk :disk, size: "#{gb}GB", name: "#{n[:name]}-disk#{i + 1}"
      end

      node.vm.provider "virtualbox" do |vb|
        vb.name   = "rhcsa-#{n[:name]}"
        vb.cpus   = n[:cpus]
        vb.memory = n[:memory]
        vb.gui    = false
        vb.check_guest_additions = false
        # DNS del host a traves del NAT (evita lentitud/fallos de resolucion)
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
      end

      # --- Comun a las 3 VMs: root/SSH, /etc/hosts, paquetes base ---
      node.vm.provision "common", type: "shell",
        path: "vagrant/provision-common.sh",
        env: { "ROLE" => n[:name], "ROOT_PASS" => ROOT_PASS, "SUBNET" => SUBNET }

      # --- Solo la workstation: repo, timer, corrector y claves SSH ---
      if n[:name] == "workstation"
        UPLOADS.each do |f|
          next unless File.exist?(File.join(File.dirname(__FILE__), f))
          node.vm.provision "upload-#{f}", type: "file",
            source: f, destination: "/tmp/lab-upload-#{f}"
        end

        node.vm.provision "workstation", type: "shell",
          path: "vagrant/provision-workstation.sh",
          env: { "ROOT_PASS" => ROOT_PASS, "SUBNET" => SUBNET }

        # Ejecuta env.sh (arma el escenario del examen). Se corre solo con
        # AUTO_ENV=1 o a demanda:  vagrant provision workstation --provision-with env
        node.vm.provision "env", type: "shell",
          run: (AUTO_ENV ? "once" : "never"),
          inline: "cd /root/rhcsa-test-paper3 && bash ./env.sh"

        node.vm.post_up_message = <<~MSG

          ==========================================================
           Laboratorio RHCSA listo
          ==========================================================
           vagrant ssh                  -> entra a la workstation
           sudo -i                      -> pasa a root
           cd /root/rhcsa-test-paper3
           ./env.sh                     -> prepara el escenario (si no usaste AUTO_ENV=1)
           exam-timer start 180         -> inicia el examen (3 horas)
           exam-timer live              -> cuenta regresiva
           exam-timer finish            -> corrige y muestra tu tiempo
           vagrant ssh servera          -> maquina de las tareas Q02-Q15
           vagrant ssh serverb          -> maquina de las tareas Q16-Q21
          ==========================================================
        MSG
      end
    end
  end
end
