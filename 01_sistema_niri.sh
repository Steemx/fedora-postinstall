#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX (UNIFICADO - Niri/noctalia-git
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

sudo -u $REAL_USER systemctl --user enable --now pipewire pipewire-pulse wireplumber
sudo -u $REAL_USER systemctl --user enable --now xdg-desktop-portal-wlr
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
vm.swappiness = 1
