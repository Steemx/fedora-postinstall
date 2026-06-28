#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX (UNIFICADO - Niri/Noctalia)
# ==============================================================================

# Colores para la terminal
VERDE='\033[0;32m'
ANUNCIAR='\033[1;34m'
ROJO='\033[0;31m'
NC='\033[0m' # Sin color

# Asegurar que el script se ejecute como root al principio
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO}Por favor, ejecuta este script usando sudo: sudo $0${NC}"
    exit 1
fi

# Guardar el usuario real para las configuraciones de carpetas y temas
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)
LOG_FILE="$USER_HOME/fedora_install_report.log"

log_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${VERDE}[OK] $2${NC}"
        echo "✅ SUCESO: $2" >> "$LOG_FILE"
    else
        echo -e "${ROJO}[ERROR] $2${NC}"
        echo "❌ FALLÓ: $2" >> "$LOG_FILE"
        exit 1
    fi
}

echo -e "${ANUNCIAR}=== INICIANDO CONFIGURACIÓN DE POST-INSTALACIÓN ===${NC}"
echo "=== REPORTE DE POST-INSTALACIÓN DE FEDORA ===" > "$LOG_FILE"
echo "Fecha: $(date)" >> "$LOG_FILE"
echo "--------------------------------------------" >> "$LOG_FILE"

echo -e "${ANUNCIAR}=== 1. Optimizando DNF ===${NC}"
cat << 'EOF' > /etc/dnf/dnf.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
best=False
#skip_if_unavailable=True
#fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOF
log_status $? "Optimización de DNF"

echo -e "${ANUNCIAR}=== 2. Instalando Repositorios RPM Fusion y Plugins ===${NC}"
/usr/bin/dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                       https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
/usr/bin/dnf -y install dnf-plugins-core
log_status $? "Repositorios RPM Fusion y Plugins"

echo -e "${ANUNCIAR}=== 3. Habilitando Flatpak and repositorio Flathub ===${NC}"
/usr/bin/dnf -y install flatpak
/usr/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
log_status $? "Repositorio Flathub"

echo -e "${ANUNCIAR}=== 4. Actualizando el sistema base ===${NC}"
/usr/bin/dnf -y update
log_status $? "Actualización del sistema base"

echo -e "${ANUNCIAR}=== 5. Instalando herramientas de compresión y utilidades ===${NC}"
/usr/bin/dnf -y install xz bzip2 unrar p7zip wl-clipboard xclip lbzip2 lzma arj lzop kitty cpio git webp-pixbuf-loader unar file-roller curl cabextract xorg-x11-font-utils fontconfig btop power-profiles-daemon xwayland-satellite
log_status $? "Herramientas de compresión y utilidades"

# Nano lineas numeradas
echo "set linenumbers" >> ~/.nanorc

echo -e "${ANUNCIAR}=== 5b. Instalando base ===${NC}"
# Habilitar repositorios Git
/usr/bin/dnf copr enable yalter/niri-git -y
/usr/bin/dnf copr enable lionheartp/Hyprland -y
echo "priority=1" | sudo tee -a /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:yalter:niri-git.repo

/usr/bin/dnf install niri noctalia-git -y

# Instalar todo el stack gráfico base
/usr/bin/dnf install qt6-qtwayland wayland-protocols-devel xdg-desktop-portal-wlr xdg-desktop-portal-gtk pipewire pipewire-pulse wireplumber kitty thunar wl-clipboard fira-code-fonts google-noto-sans-fonts cpupower gamemode -y

systemctl --user --machine="${REAL_USER}@.host" enable --now pipewire pipewire-pulse wireplumber
systemctl --user --machine="${REAL_USER}@.host" enable --now xdg-desktop-portal-wlr
log_status $? "Base"

echo -e "${ANUNCIAR}=== 6. Instalando fuentes del sistema y temas ===${NC}"
/usr/bin/dnf install -y google-noto-sans-fonts google-noto-serif-fonts liberation-fonts fira-code-fonts rsms-inter-fonts rsms-inter-vf-fonts qt6ct qt5ct papirus-icon-theme kvantum xdg-desktop-portal-kde
log_status $? "Fuentes del sistema"

echo -e "${ANUNCIAR}=== 7. Configurando Códecs y Multimedia Avanzada ===${NC}"
/usr/bin/dnf remove -y ffmpeg-free libavcodec-free libavformat-free libavutil-free libswscale-free libswresample-free libpostproc-free
/usr/bin/dnf install -y ffmpeg ffmpeg-libs libavdevice --allowerasing
/usr/bin/dnf install -y libfreeaptx libldac fdk-aac gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-plugin-libav
/usr/bin/dnf install -y intel-media-driver libva libva-utils
/usr/bin/dnf config-manager setopt fedora-cisco-openh264.enabled=1
/usr/bin/dnf install -y gstreamer1-plugin-openh264 mozilla-openh264
log_status $? "Códecs multimedia y drivers de video Intel (Instalación Directa)"

echo -e "${ANUNCIAR}=== 8. Ajustes de Rendimiento Avanzados (ZRAM y sysctl) ===${NC}"
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

echo -e "${ANUNCIAR}=== 9. Habilitando GuC/HuC para Gráficos Intel ===${NC}"
cat << 'EOF' > /etc/modprobe.d/i915.conf
options i915 enable_guc=2
options i915 enable_fbc=1
options i915 modeset=1
EOF
log_status $? "Configuración Intel GuC/HuC (GUC=3) y Dracut"

echo -e "${ANUNCIAR}=== 10. Agregando kdeconnect al Firewall (Firewalld) ===${NC}"
if /usr/bin/rpm -q firewalld &>/dev/null; then 
firewall-cmd --permanent --add-service=kdeconnect 
firewall-cmd --reload 
fi 

# Configurar el teclado latinoamericano de forma global nativa
if [ -f /etc/environment ]; then
    sed -i '/XKB_DEFAULT_LAYOUT/d' /etc/environment
    sed -i '/XKB_DEFAULT_MODEL/d' /etc/environment
fi
cat << 'EOF' >> /etc/environment
XKB_DEFAULT_LAYOUT=latam
XKB_DEFAULT_MODEL=pc105
EOF

echo -e "${ANUNCIAR}=== 11. Configurando entorno Qt ===${NC}"
sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config/environment.d"
log_status $? "Configuración entorno Qt"

echo -e "${ANUNCIAR}=== 12. Optimizando Tiempos de Arranque Final ===${NC}"
/usr/bin/systemctl disable NetworkManager-wait-online.service
/usr/bin/systemctl enable fstrim.timer
/usr/bin/systemctl enable --now power-profiles-daemon
log_status $? "Optimización de arranque final y fstrim"

echo -e "${ANUNCIAR}=== 13. Limpiando archivos temporales y caché ===${NC}"
/usr/bin/dnf clean all
/usr/bin/flatpak uninstall --unused -y
log_status $? "Limpieza del sistema"

# Configurar el arranque automático de Niri en tu .bash_profile al loguearte en la TTY1
sed -i '/# Arranque automático de Niri/,+4d' "$USER_HOME/.bash_profile" 2>/dev/null || true
cat << 'EOF' >> "$USER_HOME/.bash_profile"

# Arranque automático de Niri nativo desde TTY1
if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
    exec niri-session
fi
EOF
chown $REAL_USER:$REAL_USER "$USER_HOME/.bash_profile"

# --- COMPROBACIONES DE HARDWARE (MUESTRAN EL ESTADO REAL EN EL LOG) ---
echo -e "${ANUNCIAR}=== Ejecutando Comprobaciones y Dracut ===${NC}"
echo "=== Comprobaciones de Hardware Post-Instalación ===" >> "$LOG_FILE"
echo "Generando initramfs con Dracut..."
/usr/sbin/dracut --force -v || { echo -e "${ROJO}❌ Error crítico en dracut.${NC}"; log_status 1 "Generación de Dracut"; exit 1; }

echo -e "\n[Estado de Intel GuC]:" >> "$LOG_FILE"
/usr/bin/dmesg | grep -i guc >> "$LOG_FILE" 2>&1 || echo "No se encontraron registros de GuC" >> "$LOG_FILE"
echo -e "\n[Estado de Intel HuC]:" >> "$LOG_FILE"
/usr/bin/dmesg | grep -i huc >> "$LOG_FILE" 2>&1 || echo "No se encontraron registros de HuC" >> "$LOG_FILE"
echo -e "\n[Estado de zRAMctl]:" >> "$LOG_FILE"
/usr/bin/zramctl >> "$LOG_FILE" 2>&1 || echo "No se pudo ejecutar zramctl" >> "$LOG_FILE"

# Forzar el arranque directo en modo consola (TTY) desactivando cualquier Display Manager
systemctl set-default multi-user.target
systemctl disable gdm.service 2>/dev/null || true
systemctl disable sddm.service 2>/dev/null || true
systemctl disable greetd.service 2>/dev/null || true

# ----------------------------------------------------------------------
echo "--------------------------------------------" >> "$LOG_FILE"
echo "Proceso finalizado por completo con éxito." >> "$LOG_FILE"
/usr/bin/chown $REAL_USER:$REAL_USER "$LOG_FILE"

echo -e "${VERDE}==============================================================================${NC}"
echo -e "${VERDE} ¡PROCESO COMPLETADO! Todo se ha configurado de manera definitiva.            ${NC}"
echo -e "${VERDE} El equipo se reiniciará automáticamente en 10 segundos...                     ${NC}"
echo -e "${VERDE} Al volver te pedirá tu usuario/pass en la TTY y cargará Niri solo.             ${NC}"
echo -e "${VERDE}==============================================================================${NC}"
sleep 10
reboot
