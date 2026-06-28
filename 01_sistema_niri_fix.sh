#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 1: BASE DEL SISTEMA, OPTIMIZACIONES DNF5, COPR Y ENTORNO GRÁFICO (NIRI)
# ==============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta este script usando sudo: sudo $0"
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
LOG_FILE="$USER_HOME/fedora_sistema_install.log"

# === COLORES PARA LA TERMINAL ===
ANUNCIAR='\033[1;34m' # Azul Brillante para las secciones principales
EXITO='\033[0;32m'    # Verde para estados de suceso
ALERTA='\033[1;33m'   # Amarillo para advertencias importantes
NC='\033[0m'          # No Color (Resetear al color original de la terminal)

set +e

log_status() {
    if [ $1 -eq 0 ]; then
        echo "✅ SUCESO: $2" >> "$LOG_FILE"
        echo -e "${EXITO}--> OK: $2${NC}\n"
    else
        echo "❌ FALLÓ: $2" >> "$LOG_FILE"
        echo -e "${ALERTA}--> ATENCIÓN: Falló o se omitió $2${NC}\n"
    fi
}

echo -e "${ANUNCIAR}=== INICIANDO INSTALACIÓN DEL SISTEMA BASE Y NIRI (FEDORA 44 - DNF5) ===${NC}"
echo "=== REPORTE DE SISTEMA BASE ===" > "$LOG_FILE"
echo "Fecha: $(date)" >> "$LOG_FILE"
echo "Usuario: $REAL_USER" >> "$LOG_FILE"
echo "--------------------------------------------" >> "$LOG_FILE"

echo -e "${ANUNCIAR}=== 1. Optimizando DNF y DNF5 ===${NC}"
# Configuración para compatibilidad hacia atrás (DNF antiguo)
cat << 'EOF' > /etc/dnf/dnf.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
max_parallel_downloads=10
defaultyes=True
EOF

# Aplicar las mismas optimizaciones nativas para DNF5 en Fedora 44
mkdir -p /etc/dnf
cat << 'EOF' > /etc/dnf/dn5.conf 2>/dev/null || true
cat << 'EOF' > /etc/dnf/dnf5.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
max_parallel_downloads=10
defaultyes=True
EOF
log_status $? "Optimización de DNF y DNF5"

echo -e "${ANUNCIAR}=== 2. Instalando Repositorios RPM Fusion y Plugins ===${NC}"
FEDORA_VERSION=$(rpm -E %fedora)
/usr/bin/dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$FEDORA_VERSION".noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$FEDORA_VERSION".noarch.rpm
/usr/bin/dnf -y install dnf-plugins-core
log_status $? "Repositorios RPM Fusion y Plugins"

echo -e "${ANUNCIAR}=== 3. Habilitando Flatpak y repositorio Flathub ===${NC}"
/usr/bin/dnf -y install flatpak
/usr/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
log_status $? "Repositorio Flathub"

echo -e "${ANUNCIAR}=== 4. Actualizando el sistema base ===${NC}"
/usr/bin/dnf -y update
log_status $? "Actualización del sistema base"

echo -e "${ANUNCIAR}=== 5. Instalando herramientas de compresión y utilidades esenciales ===${NC}"
/usr/bin/dnf -y install xz bzip2 unrar p7zip wl-clipboard xclip lbzip2 lzma arj lzop \
    cpio git webp-pixbuf-loader unar file-roller curl cabextract \
    fontconfig btop power-profiles-daemon
log_status $? "Herramientas de compresión y utilidades"

echo -e "${ANUNCIAR}=== 6. Instalando base Niri/Noctalia con SDDM ===${NC}"
/usr/bin/dnf copr enable yalter/niri-git -y
/usr/bin/dnf copr enable lionheartp/Hyprland -y
echo "priority=1" | tee -a /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:yalter:niri-git.repo

# Instalación conjunta de SDDM junto al driver de control del mouse para entorno minimal
/usr/bin/dnf install -y sddm xorg-x11-drv-libinput niri noctalia-git

/usr/bin/dnf install -y \
    qt6-qtwayland wayland-protocols \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
    pipewire pipewire-pulse wireplumber \
    kitty thunar \
    fira-code-fonts google-noto-sans-fonts \
    kernel-tools gamemode

mkdir -p /usr/share/wayland-sessions
cat << 'EOF' > /usr/share/wayland-sessions/niri.desktop
[Desktop Entry]
Name=Niri (Git)
Comment=A scrollable tiling Wayland compositor (Development Branch)
Exec=niri-session
Type=Application
DesktopNames=niri
EOF

# Limpieza preventiva por si quedó rastro de configuraciones fallidas previas
rm -f /etc/sddm.conf.d/wayland.conf

systemctl set-default graphical.target
systemctl disable gdm.service 2>/dev/null || true
systemctl disable lightdm.service 2>/dev/null || true
systemctl enable --force sddm.service
log_status $? "Base Niri/Noctalia (Git) y configuración de SDDM con drivers de entrada"

echo -e "${ANUNCIAR}=== 7. Instalando fuentes del sistema y temas ===${NC}"
/usr/bin/dnf install -y \
    google-noto-sans-fonts google-noto-serif-fonts liberation-fonts fira-code-fonts \
    qt6ct qt5ct papirus-icon-theme kvantum
log_status $? "Fuentes del sistema y temas"

echo -e "${ANUNCIAR}=== 8. Configurando Códecs y Multimedia Avanzada (Swap de Free a NonFree) ===${NC}"
/usr/bin/dnf remove -y ffmpeg-free libavcodec-free libavformat-free libavutil-free \
    libswscale-free libswresample-free libpostproc-free 2>/dev/null || true
/usr/bin/dnf install -y ffmpeg ffmpeg-libs libavdevice --allowerasing
/usr/bin/dnf install -y libfreeaptx libldac fdk-aac gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly gstreamer1-plugin-libav
/usr/bin/dnf install -y intel-media-driver libva libva-utils
/usr/bin/dnf config-manager setopt fedora-cisco-openh264.enabled=1
/usr/bin/dnf install -y gstreamer1-plugin-openh264 mozilla-openh264
log_status $? "Códecs multimedia y drivers de video Intel"

echo -e "${ANUNCIAR}=== 9. Ajustes de Rendimiento Avanzados (ZRAM y sysctl) ===${NC}"
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
/usr/bin/systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
log_status $? "Ajustes de rendimiento (ZRAM y sysctl)"

echo -e "${ANUNCIAR}=== 10. Habilitando GuC/HuC para Gráficos Intel ===${NC}"
cat << 'EOF' > /etc/modprobe.d/i915.conf
options i915 enable_guc=2
options i915 enable_fbc=1
options i915 modeset=1
EOF
log_status $? "Configuración Intel GuC/HuC"

echo -e "${ANUNCIAR}=== 11. Configurando Distribución de Teclado y Entorno ===${NC}"
if [ -f /etc/environment ]; then
    sed -i '/XKB_DEFAULT_LAYOUT/d' /etc/environment
    sed -i '/XKB_DEFAULT_MODEL/d' /etc/environment
fi
cat << 'EOF' >> /etc/environment
XKB_DEFAULT_LAYOUT=latam
XKB_DEFAULT_MODEL=pc105
EOF

sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config/environment.d"
cat << 'EOF' | sudo -u "$REAL_USER" tee "$USER_HOME/.config/environment.d/qt.conf" > /dev/null
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
QT_AUTO_SCREEN_SCALE_FACTOR=1
EOF
log_status $? "Configuración entorno de teclado y Qt"

echo -e "${ANUNCIAR}=== 12. Optimización de servicios y arranque ===${NC}"
/usr/bin/systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
/usr/bin/systemctl enable fstrim.timer 2>/dev/null || true
/usr/bin/systemctl enable --now power-profiles-daemon 2>/dev/null || true
log_status $? "Optimización de arranque y fstrim"

echo -e "${ANUNCIAR}=== Comprobaciones de Hardware Finales ===${NC}"
echo "Generando initramfs con Dracut (esta sección generará mucho texto rápido)..."
/usr/sbin/dracut --force --verbose || echo -e "${ALERTA}⚠️ Advertencia en Dracut${NC}"

echo -e "\n[Estado de Intel GuC/HuC]:" >> "$LOG_FILE"
/usr/bin/dmesg | grep -iE "guc|huc" >> "$LOG_FILE" 2>&1
/usr/bin/dnf clean all

echo "--------------------------------------------" >> "$LOG_FILE"
echo "PROCESO BASE TERMINADO. Ya puedes reiniciar e iniciar en Niri." >> "$LOG_FILE"
/usr/bin/chown "$REAL_USER":"$REAL_USER" "$LOG_FILE"

echo -e "${EXITO}=============================================================================="
echo " ¡BASE DEL SISTEMA CONFIGURADA! El entorno Niri está listo."
echo " Se recomienda reiniciar ahora. Al volver, ejecuta el script de aplicaciones."
echo -e "==============================================================================${NC}"
sleep 5
