#!/usr/bin/env bash

# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX (UNIFICADO - LXQT OPTIMIZADO)
# ==============================================================================

# Asegurar que el script se ejecute como root al principio
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script usando sudo: sudo $0"
  exit 1
fi

# Guardar el usuario real para las configuraciones de carpetas y temas
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)
LOG_FILE="$USER_HOME/fedora_install_report.log"

log_status() {
  if [ $1 -eq 0 ]; then
    echo "✅ SUCESO: $2" >> "$LOG_FILE"
  else
    echo "❌ FALLÓ: $2" >> "$LOG_FILE"
  fi
}

echo "=== INICIANDO CONFIGURACIÓN DE POST-INSTALACIÓN ==="
echo "=== REPORTE DE POST-INSTALACIÓN DE FEDORA ===" > "$LOG_FILE"
echo "Fecha: $(date)" >> "$LOG_FILE"
echo "--------------------------------------------" >> "$LOG_FILE"

echo "=== 1. Optimizando DNF ==="
cat << 'EOF' > /etc/dnf/dnf.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
skip_if_unavailable=True
fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOF
log_status $? "Optimización de DNF"

echo "=== 2. Instalando Repositorios RPM Fusion y Plugins ==="
/usr/bin/dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
               https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
/usr/bin/dnf -y install dnf-plugins-core
log_status $? "Repositorios RPM Fusion y Plugins"

echo "=== 3. Habilitando Flatpak y repositorio Flathub ==="
/usr/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
log_status $? "Repositorio Flathub"

echo "=== 4. Actualizando el sistema base ==="
/usr/bin/dnf -y update && /usr/bin/dnf group upgrade -y core && /usr/bin/dnf4 group install -y core
log_status $? "Actualización del sistema base y Core"

echo "=== 5. Instalando herramientas de compresión y utilidades ==="
/usr/bin/dnf -y install xz bzip2 unrar p7zip lbzip2 arj lzma arj lzop cpio webp-pixbuf-loader unar file-roller curl cabextract xorg-x11-font-utils fontconfig btop
log_status $? "Herramientas de compresión y utilidades"

echo "=== 6. Instalando fuentes del sistema ==="
/usr/bin/dnf install -y google-noto-sans-fonts google-noto-serif-fonts liberation-fonts
log_status $? "Fuentes del sistema"

echo "=== 7. Configurando Códecs y Multimedia Avanzada ==="
/usr/bin/dnf install -y libfreeaptx libldac fdk-aac && \
/usr/bin/dnf4 group install -y multimedia && \
/usr/bin/dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing && \
/usr/bin/dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin && \
/usr/bin/dnf group install -y sound-and-video && \
/usr/bin/dnf install -y ffmpeg ffmpeg-libs libva libva-utils && \
/usr/bin/dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing && \
/usr/bin/dnf install -y libva-intel-driver && \
/usr/bin/dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264 && \
/usr/bin/dnf config-manager setopt fedora-cisco-openh264.enabled=1
log_status $? "Códecs multimedia y drivers de video Intel"

echo "=== 8. Ajustes de Rendimiento Avanzados (ZRAM y sysctl) ==="
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

cat << 'EOF' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram
compression-algorithm = lz4
swap-priority = 100
fs-type = swap
EOF
/usr/bin/systemctl daemon-reload
/usr/bin/systemctl restart systemd-zram-setup@zram0.service
log_status $? "Ajustes de rendimiento (ZRAM y sysctl)"

echo "=== 9. Habilitando GuC/HuC para Gráficos Intel ==="
cat << 'EOF' > /etc/modprobe.d/i915.conf
options i915 enable_guc=3
options i915 enable_fbc=1
EOF
echo "Generando initramfs con Dracut..."
/usr/sbin/dracut --force || { echo "❌ Error crítico en dracut."; log_status 1 "Generación de Dracut"; exit 1; }
log_status $? "Configuración Intel GuC/HuC (GUC=3) y Dracut"

echo "=== 10. Configurando el Firewall (KDE Connect) ==="
/usr/bin/firewall-cmd --permanent --add-service=kdeconnect
/usr/bin/firewall-cmd --reload
log_status $? "Configuración del Firewall (KDE Connect)"

echo "=== 11. Detección Inteligente y Configuración de Teclado (LXQt + Miriway) ==="
CURRENT_DESKTOP=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:lower:]' '[:upper:]')
SESSION_TYPE=$(echo "$XDG_SESSION_TYPE" | tr '[:lower:]' '[:upper:]')

if [[ "$CURRENT_DESKTOP" == *"LXQT"* && ("$SESSION_TYPE" == *"WAYLAND"* || -f /usr/bin/miriway || -d /etc/xdg/xdg-miriway) ]]; then
    echo "Entorno LXQt con Wayland/Miriway detectado. Configurando teclado latinoamericano..."
    if [ -f /etc/environment ]; then
        sed -i '/XKB_DEFAULT_LAYOUT/d' /etc/environment
        sed -i '/XKB_DEFAULT_MODEL/d' /etc/environment
    fi
    echo "XKB_DEFAULT_LAYOUT=latam" >> /etc/environment
    echo "XKB_DEFAULT_MODEL=pc105" >> /etc/environment

    MIRIWAY_CONFIG="$USER_HOME/.config/miriway-shell.config"
    sudo -u $REAL_USER mkdir -p "$(dirname "$MIRIWAY_CONFIG")"
    if [ -f "$MIRIWAY_CONFIG" ]; then
        sudo -u $REAL_USER sed -i '/app-env-amend=/d' "$MIRIWAY_CONFIG"
    fi
    sudo -u $REAL_USER echo "app-env-amend=XKB_DEFAULT_LAYOUT=latam:XKB_DEFAULT_MODEL=pc105" >> "$MIRIWAY_CONFIG"
    log_status 0 "Configuración de teclado latinoamericano para LXQt-Miriway"
else
    echo "Entorno diferente detectado, saltando inyección de teclado latinoamericano."
    log_status 0 "Teclado latinoamericano (Saltado - No requerido)"
fi

echo "=== 12. Configurando Temas para Aplicaciones Flatpak ==="
/usr/bin/flatpak override --system --filesystem=$USER_HOME/.themes
/usr/bin/flatpak override --system --env=GTK_THEME=my-theme
/usr/bin/flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=/usr/share/themes:ro
log_status $? "Overrides de temas para Flatpak"

echo "=== 13. Instalando Programas del Sistema (DNF) ==="
/usr/bin/dnf install -y steam kde-connect
if [ $? -eq 0 ] || /usr/bin/rpm -q steam &>/dev/null; then
  log_status 0 "Instalación de programas DNF (Steam, KDE Connect)"
else
  log_status 1 "Instalación de programas DNF (Steam, KDE Connect)"
fi

echo "=== 14. Instalando Aplicaciones Flatpak ==="
/usr/bin/flatpak update --appstream -y
# Usamos env TERM=dumb para ocultar barras de progreso animadas y evitar caracteres ANSI corruptos
env TERM=dumb /usr/bin/flatpak install --system -y flathub com.discordapp.Discord \
                                                              com.github.tchx84.Flatseal \
                                                              io.github.flattool.Warehouse \
                                                              org.telegram.desktop \
                                                              io.github.kolunmi.Bazaar 2>&1 | grep -v -E "([0-9]+%)"
if [ $? -eq 0 ] || /usr/bin/flatpak list --system | grep -q "Discord"; then
  log_status 0 "Instalación de aplicaciones Flatpak"
else
  log_status 1 "Instalación de aplicaciones Flatpak"
fi

echo "=== 15. Configurando aplicaciones en Inicio Automático (Minimizadas) ==="
sudo -u $REAL_USER mkdir -p $USER_HOME/.config/autostart

sudo -u $REAL_USER cat << 'EOF' > $USER_HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop
[Desktop Entry]
Type=Application
Name=KDE Connect Indicator
Exec=kdeconnect-indicator
Icon=kdeconnect
Terminal=false
Categories=Network;
EOF

sudo -u $REAL_USER cat << 'EOF' > $USER_HOME/.config/autostart/com.discordapp.Discord.desktop
[Desktop Entry]
Type=Application
Name=Discord
Exec=/usr/bin/flatpak run com.discordapp.Discord --start-minimized
Icon=com.discordapp.Discord
Terminal=false
Categories=Network;InstantMessaging;
EOF

sudo -u $REAL_USER cat << 'EOF' > $USER_HOME/.config/autostart/org.telegram.desktop.desktop
[Desktop Entry]
Type=Application
Name=Telegram
Exec=/usr/bin/flatpak run org.telegram.desktop -startintray
Icon=telegram
Terminal=false
Categories=Network;InstantMessaging;
EOF
log_status $? "Configuración de inicio automático minimizado"

echo "=== 16. Optimizando Tiempos de Arranque Final ==="
/usr/bin/systemctl disable NetworkManager-wait-online.service
/usr/bin/systemctl enable fstrim.timer
log_status $? "Optimización de arranque final y fstrim"

echo "=== 17. Limpiando archivos temporales y caché ==="
/usr/bin/dnf clean all
/usr/bin/flatpak uninstall --unused -y
log_status $? "Limpieza del sistema"

echo "=== 18. Generando pantalla de reporte para el próximo inicio ==="
/usr/bin/update-desktop-database /var/lib/flatpak/exports/share/applications &>/dev/null
SCRIPT_LOG_VIEWER="$USER_HOME/.show_install_log.sh"
sudo -u $REAL_USER cat << EOF > "$SCRIPT_LOG_VIEWER"
#!/usr/bin/env bash
echo "================================================================="
cat "$LOG_FILE"
echo "================================================================="
echo ""
echo "Presiona cualquier tecla para cerrar esta ventana..."
read -n 1
rm -- "\$0"
rm -f "$USER_HOME/.config/autostart/show_log.desktop"
EOF
chmod +x "$SCRIPT_LOG_VIEWER"

sudo -u $REAL_USER cat << EOF > $USER_HOME/.config/autostart/show_log.desktop
[Desktop Entry]
Type=Application
Name=Show Install Log
Exec=qterminal -e "/usr/bin/bash -c '$SCRIPT_LOG_VIEWER'"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "--------------------------------------------" >> "$LOG_FILE"
echo "Proceso finalizado por completo con éxito." >> "$LOG_FILE"
/usr/bin/chown $REAL_USER:$REAL_USER "$LOG_FILE"

echo "=============================================================================="
echo " ¡PROCESO COMPLETADO! Todo se ha configurado e instalado con éxito."
echo " El equipo se reiniciará automáticamente en 5 segundos..."
echo " Al iniciar sesión tu teclado estará en Latinoamericano y apps activas."
echo "=============================================================================="
sleep 5
/usr/sbin/reboot