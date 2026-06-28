#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX (NIRI + NOCTALIA + SDDM)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta este script usando sudo: sudo $0"
    exit 1
fi

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
echo "Usuario: $REAL_USER" >> "$LOG_FILE"
echo "--------------------------------------------" >> "$LOG_FILE"

echo "=== 1. Optimizando DNF ==="
cat << 'EOF' > /etc/dnf/dnf.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
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
/usr/bin/dnf -y install flatpak
/usr/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
log_status $? "Repositorio Flathub"

echo "=== 4. Actualizando el sistema base ==="
/usr/bin/dnf -y update
log_status $? "Actualización del sistema base"

echo "=== 5. Instalando herramientas de compresión y utilidades ==="
/usr/bin/dnf -y install xz bzip2 unrar p7zip wl-clipboard xclip lbzip2 lzma arj lzop \
    cpio git webp-pixbuf-loader unar file-roller curl cabextract xorg-x11-font-utils \
    fontconfig btop power-profiles-daemon xwayland-satellite
log_status $? "Herramientas de compresión y utilidades"

echo "=== 5b. Instalando base Niri/Noctalia con SDDM ==="
/usr/bin/dnf copr enable yalter/niri-git -y
/usr/bin/dnf copr enable lionheartp/Hyprland -y
echo "priority=1" | tee -a /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:yalter:niri-git.repo

/usr/bin/dnf install -y niri noctalia-git

/usr/bin/dnf install -y \
    sddm \
    qt6-qtwayland wayland-protocols \
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
    pipewire pipewire-pulse wireplumber \
    kitty thunar wl-clipboard \
    fira-code-fonts google-noto-sans-fonts \
    kernel-tools gamemode

mkdir -p /usr/share/wayland-sessions
cat << 'EOF' > /usr/share/wayland-sessions/niri.desktop
[Desktop Entry]
Name=Niri
Comment=A scrollable tiling Wayland compositor
Exec=niri-session
Type=Application
DesktopNames=niri
EOF

systemctl enable sddm

sudo -u $REAL_USER systemctl --user enable --now pipewire pipewire-pulse wireplumber
sudo -u $REAL_USER systemctl --user enable --now xdg-desktop-portal-wlr

sudo -u $REAL_USER mkdir -p $USER_HOME/.config/niri

if [ -f /usr/share/niri/config.kdl ]; then
    cp /usr/share/niri/config.kdl $USER_HOME/.config/niri/config.kdl
    echo "✅ Copiado config.kdl por defecto"
else
    sudo -u $REAL_USER bash -c 'niri validate --print-default-config > $HOME/.config/niri/config.kdl'
    echo "⚠️ Usado fallback: niri validate"
fi

sudo -u $REAL_USER bash -c '
if grep -q "spawn-at-startup" $HOME/.config/niri/config.kdl; then
    sed -i "0,/spawn-at-startup/{s/spawn-at-startup/spawn-at-startup \"noctalia-shell\"\n    spawn-at-startup/}" $HOME/.config/niri/config.kdl
else
    echo -e "\nspawn-at-startup \"noctalia-shell\"" >> $HOME/.config/niri/config.kdl
fi
'

chown -R $REAL_USER:$REAL_USER $USER_HOME/.config/niri
log_status $? "Base Niri/Noctalia con SDDM"

echo "=== 6. Instalando fuentes del sistema y temas ==="
/usr/bin/dnf install -y \
    google-noto-sans-fonts google-noto-serif-fonts liberation-fonts fira-code-fonts \
    rsms-inter-fonts rsms-inter-vf-fonts qt6ct qt5ct papirus-icon-theme kvantum
log_status $? "Fuentes del sistema y temas"

echo "=== 7. Configurando Códecs y Multimedia Avanzada ==="
/usr/bin/dnf remove -y ffmpeg-free libavcodec-free libavformat-free libavutil-free \
    libswscale-free libswresample-free libpostproc-free

/usr/bin/dnf install -y ffmpeg ffmpeg-libs libavdevice --allowerasing
/usr/bin/dnf install -y libfreeaptx libldac fdk-aac gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly gstreamer1-plugin-libav
/usr/bin/dnf install -y intel-media-driver libva libva-utils

/usr/bin/dnf config-manager setopt fedora-cisco-openh264.enabled=1
/usr/bin/dnf install -y gstreamer1-plugin-openh264 mozilla-openh264
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
options i915 enable_guc=2
options i915 enable_fbc=1
options i915 modeset=1
EOF
log_status $? "Configuración Intel GuC/HuC"

echo "=== 10. Eliminando Firewall (Firewalld) ==="
/usr/bin/systemctl stop firewalld.service 2>/dev/null || true
/usr/bin/dnf remove -y firewalld

if ! grep -q "exclude=" /etc/dnf/dnf.conf; then
    echo "exclude=firewalld" >> /etc/dnf/dnf.conf
else
    sed -i 's/exclude=/exclude=firewalld,/g' /etc/dnf/dnf.conf
fi

if [ -f /etc/environment ]; then
    sed -i '/XKB_DEFAULT_LAYOUT/d' /etc/environment
    sed -i '/XKB_DEFAULT_MODEL/d' /etc/environment
fi
cat << 'EOF' >> /etc/environment
XKB_DEFAULT_LAYOUT=latam
XKB_DEFAULT_MODEL=pc105
EOF
log_status $? "Eliminación de firewalld y configuración de teclado"

echo "=== 11. Instalando Programas del Sistema (DNF) ==="
/usr/bin/dnf install -y --setopt=install_weak_deps=False steam kde-connect firefox
if [ $? -eq 0 ] || /usr/bin/rpm -q steam &>/dev/null; then
    log_status 0 "Instalación de programas DNF (Steam, KDE Connect, Firefox)"
else
    log_status 1 "Instalación de programas DNF (Steam, KDE Connect, Firefox)"
fi

echo "=== 12. Configurando aplicaciones en Inicio Automático ==="
sudo -u $REAL_USER mkdir -p $USER_HOME/.config/autostart

cat << 'EOF' | sudo -u $REAL_USER tee $USER_HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop > /dev/null
[Desktop Entry]
Type=Application
Name=KDE Connect Indicator
Exec=kdeconnect-indicator
Icon=kdeconnect
Terminal=false
Categories=Network;
EOF

cat << 'EOF' | sudo -u $REAL_USER tee $USER_HOME/.config/autostart/org.telegram.desktop.desktop > /dev/null
[Desktop Entry]
Type=Application
Name=Telegram
Exec=sh -c "sleep 20 && /usr/bin/flatpak run org.telegram.desktop -startintray"
Icon=telegram
Terminal=false
Categories=Network;InstantMessaging;
EOF
log_status $? "Configuración de inicio automático"

echo "=== 12a. Configurando entorno Qt para Wayland ==="
sudo -u $REAL_USER mkdir -p $USER_HOME/.config/environment.d
cat << 'EOF' | sudo -u $REAL_USER tee $USER_HOME/.config/environment.d/qt.conf > /dev/null
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_AUTO_SCREEN_SCALE_FACTOR=1
EOF
log_status $? "Configuración entorno Qt"

echo "=== 13. Instalando Aplicaciones Flatpak ==="
/usr/bin/flatpak update --appstream -y
/usr/bin/flatpak install --system -y flathub \
    com.discordapp.Discord \
    com.vysp3r.ProtonPlus \
    com.github.tchx84.Flatseal \
    io.github.flattool.Warehouse \
    org.telegram.desktop \
    io.github.kolunmi.Bazaar 2>&1 | grep -v -E "([0-9]+%)"

if [ $? -eq 0 ] || /usr/bin/flatpak list --system | grep -q "Discord"; then
    log_status 0 "Instalación de aplicaciones Flatpak"
else
    log_status 1 "Instalación de aplicaciones Flatpak"
fi

echo "=== 14. Optimizando Tiempos de Arranque ==="
/usr/bin/systemctl disable NetworkManager-wait-online.service
/usr/bin/systemctl enable fstrim.timer
/usr/bin/systemctl enable --now power-profiles-daemon
log_status $? "Optimización de arranque y fstrim"

echo "=== 15. Limpiando archivos temporales y caché ==="
/usr/bin/dnf clean all
/usr/bin/flatpak uninstall --unused -y
log_status $? "Limpieza del sistema"

echo "=== 16. Generando pantalla de reporte para el próximo inicio ==="
/usr/bin/update-desktop-database /var/lib/flatpak/exports/share/applications &>/dev/null

SCRIPT_LOG_VIEWER="$USER_HOME/.show_install_log.sh"
cat << EOF | sudo -u $REAL_USER tee "$SCRIPT_LOG_VIEWER" > /dev/null
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

cat << EOF | sudo -u $REAL_USER tee $USER_HOME/.config/autostart/show_log.desktop > /dev/null
[Desktop Entry]
Type=Application
Name=Show Install Log
Exec=kitty -e '/usr/bin/bash -c "$SCRIPT_LOG_VIEWER"'
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "=== Comprobaciones de Hardware Post-Instalación ===" >> "$LOG_FILE"
echo "Generando initramfs con Dracut..."
/usr/sbin/dracut --force -v || { echo "❌ Error crítico en dracut."; log_status 1 "Generación de Dracut"; exit 1; }

echo -e "\n[Estado de Intel GuC]:" >> "$LOG_FILE"
/usr/bin/dmesg | grep -i guc >> "$LOG_FILE" 2>&1 || echo "No se encontraron registros de GuC" >> "$LOG_FILE"

echo -e "\n[Estado de Intel HuC]:" >> "$LOG_FILE"
/usr/bin/dmesg | grep -i huc >> "$LOG_FILE" 2>&1 || echo "No se encontraron registros de HuC" >> "$LOG_FILE"

echo -e "\n[Estado de zRAMctl]:" >> "$LOG_FILE"
/usr/bin/zramctl >> "$LOG_FILE" 2>&1 || echo "No se pudo ejecutar zramctl" >> "$LOG_FILE"

echo "--------------------------------------------" >> "$LOG_FILE"
echo "Proceso finalizado por completo con éxito." >> "$LOG_FILE"
/usr/bin/chown $REAL_USER:$REAL_USER "$LOG_FILE"

echo "=============================================================================="
echo " ¡PROCESO COMPLETADO! Todo se ha configurado de manera definitiva."
echo " El equipo se reiniciará automáticamente en 10 segundos..."
echo " Al volver deberías ver el greeter de SDDM."
echo " Selecciona la sesión 'Niri' antes de poner tu contraseña."
echo "=============================================================================="
sleep 10
reboot
