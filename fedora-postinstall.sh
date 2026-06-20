#!/usr/bin/env bash

# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX
# ==============================================================================

# Asegurar que el script se ejecute como root para las tareas del sistema
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script usando sudo: sudo $0"
  exit 1
fi

# Guardar el usuario real para las configuraciones de Flatpak y Autoarranque
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)

echo "=== 1. Optimizando DNF ==="
cat << 'EOF' > /etc/dnf/dnf.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True
#fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOF

echo "=== 2. Instalando Repositorios RPM Fusion y Plugins ==="
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
               https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

dnf -y install dnf-plugins-core

echo "=== 3. Habilitando Flatpak y repositorio Flathub ==="
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "=== 4. Actualizando el sistema base ==="
dnf -y update
dnf group upgrade -y core
dnf4 group install -y core

echo "=== 5. Instalando herramientas de compresión y utilidades ==="
dnf -y install xz bzip2 unrar p7zip lbzip2 arj lzma arj lzop cpio webp-pixbuf-loader unar file-roller curl cabextract xorg-x11-font-utils fontconfig btop

echo "=== 6. Instalando fuentes del sistema ==="
dnf install -y google-noto-sans-fonts google-noto-serif-fonts liberation-fonts

echo "=== 7. Configurando Códecs y Multimedia Avanzada ==="
dnf install -y libfreeaptx libldac fdk-aac
dnf4 group install -y multimedia
dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing
dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf group install -y sound-and-video
dnf install -y ffmpeg ffmpeg-libs libva libva-utils

# Drivers específicos de Intel para aceleración por hardware
dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing
dnf install -y libva-intel-driver

# Soporte OpenH264 para Firefox
dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
dnf config-manager setopt fedora-cisco-openh264.enabled=1

echo "=== 8. Optimizando Tiempos de Arranque y Red ==="
systemctl disable NetworkManager-wait-online.service
systemctl enable fstrim.timer

echo "=== 9. Configurando Temas para Aplicaciones Flatpak ==="
flatpak override --system --filesystem=$USER_HOME/.themes
flatpak override --system --env=GTK_THEME=my-theme
flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=/usr/share/themes:ro

echo "=== 10. Habilitando GuC/HuC para Gráficos Intel ==="
cat << 'EOF' > /etc/modprobe.d/i915.conf
options i915 enable_guc=2
options i915 enable_fbc=1
EOF

echo "Generando initramfs con Dracut (esto puede tardar un poco, espera por favor)..."
dracut --force || { echo "❌ Error crítico: falló la generación del initramfs con dracut. Script detenido."; exit 1; }

echo "=== 11. Configurando el Firewall (KDE Connect y mDNS) ==="
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=kdeconnect
firewall-cmd --permanent --add-service=mdns
firewall-cmd --reload

echo "=== 12. Ajustes de Rendimiento Avanzados (ZRAM y sysctl) ==="
# Ajuste fino de memoria virtual para 8GB RAM y monitoreo de archivos
cat << 'EOF' > /etc/sysctl.d/99-zram-tune.conf
vm.swappiness = 180
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
vm.watermark_scale_factor = 125
vm.dirty_ratio = 10        
vm.dirty_background_ratio = 5       
vm.watermark_boost_factor = 0
fs.inotify.max_user_watches = 524288
EOF

# Configuración del generador ZRAM (Compresión LZ4 y 100% de la RAM)
cat << 'EOF' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = lz4
swap-priority = 100
fs-type = swap
EOF
systemctl daemon-reload
systemctl restart systemd-zram-setup@zram0.service

echo "=== 13. Instalando Programas del Sistema (DNF) ==="
# Añadir repositorio de Tailscale e instalar junto con el resto
dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf install -y tailscale steam kdeconnect
systemctl enable --now tailscaled

echo "=== 14. Instalando Aplicaciones Flatpak ==="
flatpak install -y flathub com.discordapp.Discord \
                                              com.github.tchx84.Flatseal \
                                              io.github.marcomotta.Warehouse \
                                              io.github.fushandzhiguan.Bazaar \
                                              org.telegram.desktop

echo "=== 15. Configurando aplicaciones en Inicio Automático (Minimizadas) ==="
# Asegurar que exista la carpeta autostart en el espacio de usuario
mkdir -p $USER_HOME/.config/autostart

# KDE Connect (Añadir flag para iniciar en segundo plano)
cat << 'EOF' > $USER_HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop
[Desktop Entry]
Type=Application
Name=KDE Connect Indicator
Exec=kdeconnect-indicator
Icon=kdeconnect
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# Discord (Minimizado)
cat << 'EOF' > $USER_HOME/.config/autostart/com.discordapp.Discord.desktop
[Desktop Entry]
Type=Application
Name=Discord
Exec=flatpak run com.discordapp.Discord --start-minimized
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

# Telegram (Minimizado)
cat << 'EOF' > $USER_HOME/.config/autostart/org.telegram.desktop.desktop
[Desktop Entry]
Type=Application
Name=Telegram
Exec=flatpak run org.telegram.desktop -startintray
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "=== 16. Limpiando archivos temporales y caché ==="
dnf clean all
flatpak uninstall --unused -y

echo "=============================================================================="
echo " ¡Todo listo! El sistema se ha configurado y limpiado con éxito."
echo " El equipo se reiniciará automáticamente en 5 segundos..."
echo "=============================================================================="
sleep 5
reboot
