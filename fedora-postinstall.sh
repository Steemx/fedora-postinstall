#!/usr/bin/env bash

# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX (UNIFICADO - LXQT + LABWC)
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
#fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOF
log_status $? "Optimización de DNF"

echo "=== 2. Instalando Repositorios RPM Fusion y Plugins ==="
/usr/bin/dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
               https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
/usr/bin/dnf -y install dnf-plugins-core
log_status $? "Repositorios RPM Fusion y Plugins"

echo "=== 3. Habilitando Flatpak and repositorio Flathub ==="
/usr/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
log_status $? "Repositorio Flathub"

echo "=== 4. Actualizando el sistema base ==="
/usr/bin/dnf -y update
log_status $? "Actualización del sistema base"

echo "=== 5. Instalando herramientas de compresión y utilidades ==="
/usr/bin/dnf -y install xz bzip2 unrar p7zip lbzip2 arj lzma arj lzop cpio webp-pixbuf-loader unar file-roller curl cabextract xorg-x11-font-utils fontconfig btop
log_status $? "Herramientas de compresión y utilidades"

echo "=== 6. Instalando fuentes del sistema ==="
/usr/bin/dnf install -y google-noto-sans-fonts google-noto-serif-fonts liberation-fonts
log_status $? "Fuentes del sistema"

echo "=== 7. Configurando Códecs y Multimedia Avanzada ==="
# 1. Resolver el conflicto principal de ffmpeg reemplazando la versión libre por la de RPM Fusion
/usr/bin/dnf swap -y ffmpeg-free ffmpeg --allowerasing

# 2. Instalar librerías complementarias de audio y códecs externos
/usr/bin/dnf install -y libfreeaptx libldac fdk-aac ffmpeg-libs libva libva-utils

# 3. Instalación/Actualización del grupo multimedia usando la sintaxis nativa de DNF5
/usr/bin/dnf group upgrade -y "Sound and Video" --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin --allowerasing

# 4. Configurar OpenH264 y drivers de video nativos con aceleración completa para Intel Celeron N4020
/usr/bin/dnf install -y gstreamer1-plugin-openh264 mozilla-openh264
/usr/bin/dnf config-manager setopt fedora-cisco-openh264.enabled=1
/usr/bin/dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing

log_status $? "Códecs multimedia y drivers de video Intel (RPM Fusion)"

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

echo "=== 10. Eliminando por completo el Firewall (Firewalld) ==="
/usr/bin/systemctl stop firewalld.service 2>/dev/null || true
/usr/bin/dnf remove -y firewalld
if ! grep -q "exclude=" /etc/dnf/dnf.conf; then
  echo "exclude=firewalld" >> /etc/dnf/dnf.conf
else
  sed -i 's/exclude=/exclude=firewalld,/g' /etc/dnf/dnf.conf
fi
log_status $? "Eliminación completa y bloqueo de firewalld"

echo "=== 11. Instalando Labwc y Teclado Latam (Miriway Intacto) ==="
# 1. Instalar el compositor Labwc y la sesión de Wayland (usando sintaxis limpia DNF5)
/usr/bin/dnf install -y labwc lxqt-wayland-session

# 2. Configurar el teclado latinoamericano de forma global nativa
if [ -f /etc/environment ]; then
    sed -i '/XKB_DEFAULT_LAYOUT/d' /etc/environment
    sed -i '/XKB_DEFAULT_MODEL/d' /etc/environment
fi
cat << 'EOF' >> /etc/environment
XKB_DEFAULT_LAYOUT=latam
XKB_DEFAULT_MODEL=pc105
EOF

# 3. Forzar el mapa de teclado en el archivo de sesión de LXQt del usuario
LXQT_SESSION_CONF="$USER_HOME/.config/lxqt/session.conf"
sudo -u $REAL_USER mkdir -p "$(dirname "$LXQT_SESSION_CONF")"
if [ -f "$LXQT_SESSION_CONF" ]; then
    sudo -u $REAL_USER sed -i '/XKB_DEFAULT_LAYOUT/d' "$LXQT_SESSION_CONF"
    sudo -u $REAL_USER sed -i '/XKB_DEFAULT_MODEL/d' "$LXQT_SESSION_CONF"
fi
sudo -u $REAL_USER cat << 'EOF' >> "$LXQT_SESSION_CONF"

[Environment]
XKB_DEFAULT_LAYOUT=latam
XKB_DEFAULT_MODEL=pc105
EOF
log_status $? "Instalación de Labwc y configuración de teclado Latam"

echo "=== 12. Configurando Temas para Aplicaciones Flatpak ==="
/usr/bin/flatpak override --system --filesystem=$USER_HOME/.themes
/usr/bin/flatpak override --system --env=GTK_THEME=my-theme
/usr/bin/flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=/usr/share/themes:ro
log_status $? "Overrides de temas para Flatpak"

echo "=== 13. Instalando Programas del Sistema (DNF) ==="
/usr/bin/dnf install -y --setopt=install_weak_deps=False steam kde-connect firefox
if [ $? -eq 0 ] || /usr/bin/rpm -q steam &>/dev/null; then
  log_status 0 "Instalación de programas DNF (Steam, KDE Connect, Firefox)"
else
  log_status 1 "Instalación de programas DNF (Steam, KDE Connect, Firefox)"
fi

echo "=== 14. Instalando Aplicaciones Flatpak ==="
/usr/bin/flatpak update --appstream -y
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
echo " ¡PROCESO COMPLETADO! Todo se ha configurado de manera definitiva."
echo " El equipo se reiniciará automáticamente en 10 segundos para que leas..."
echo " Al volver, cambia la sesión a 'LXQt (Wayland)' o Labwc si aparece."
echo "=============================================================================="
sleep 10
/usr/sbin/reboot
