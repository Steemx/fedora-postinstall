#!/usr/bin/env bash

# ==============================================================================
# SCRIPT DE POST-INSTALACIÓN PARA FEDORA LINUX (DOS FASES CON CONTROL DE RED)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script usando sudo: sudo $0"
  exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$REAL_USER)
LOG_FILE="$USER_HOME/fedora_install_report.log"
FASE_FILE="$USER_HOME/.fedora_postinstall_fase"

log_status() {
  if [ $1 -eq 0 ]; then
    echo "✅ SUCESO: $2" >> "$LOG_FILE"
  else
    echo "❌ FALLÓ: $2" >> "$LOG_FILE"
  fi
}

# DETERMINAR EN QUÉ FASE NOS ENCONTRAMOS
if [ ! -f "$FASE_FILE" ]; then
  # ----------------------------------------------------------------------------
  # FASE 1: CONFIGURACIÓN BASE DEL SISTEMA Y OPTIMIZACIONES
  # ----------------------------------------------------------------------------
  echo "=== INICIANDO FASE 1: Configuración del Sistema Base ==="
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
  dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                 https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
  dnf -y install dnf-plugins-core
  log_status $? "Repositorios RPM Fusion y Plugins"

  echo "=== 3. Habilitando Flatpak y repositorio Flathub ==="
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  log_status $? "Repositorio Flathub"

  echo "=== 4. Actualizando el sistema base ==="
  dnf -y update && dnf group upgrade -y core && dnf4 group install -y core
  log_status $? "Actualización del sistema base y Core"

  echo "=== 5. Instalando herramientas de compresión y utilidades ==="
  dnf -y install xz bzip2 unrar p7zip lbzip2 arj lzma arj lzop cpio webp-pixbuf-loader unar file-roller curl cabextract xorg-x11-font-utils fontconfig btop
  log_status $? "Herramientas de compresión y utilidades"

  echo "=== 6. Instalando fuentes del sistema ==="
  dnf install -y google-noto-sans-fonts google-noto-serif-fonts liberation-fonts
  log_status $? "Fuentes del sistema"

  echo "=== 7. Configurando Códecs y Multimedia Avanzada ==="
  dnf install -y libfreeaptx libldac fdk-aac && \
  dnf4 group install -y multimedia && \
  dnf swap -y 'ffmpeg-free' 'ffmpeg' --allowerasing && \
  dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin && \
  dnf group install -y sound-and-video && \
  dnf install -y ffmpeg ffmpeg-libs libva libva-utils && \
  dnf swap -y libva-intel-media-driver intel-media-driver --allowerasing && \
  dnf install -y libva-intel-driver && \
  dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264 && \
  dnf config-manager setopt fedora-cisco-openh264.enabled=1
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
  systemctl daemon-reload
  systemctl restart systemd-zram-setup@zram0.service
  log_status $? "Ajustes de rendimiento (ZRAM y sysctl)"

  echo "=== 9. Habilitando GuC/HuC para Gráficos Intel ==="
  cat << 'EOF' > /etc/modprobe.d/i915.conf
options i915 enable_guc=3
options i915 enable_fbc=1
EOF
  echo "Generando initramfs con Dracut..."
  dracut --force || { echo "❌ Error crítico en dracut."; log_status 1 "Generación de Dracut"; exit 1; }
  log_status $? "Configuración Intel GuC/HuC y Dracut"

  # Preparar el terreno para que al reiniciar el usuario ejecute la Fase 2
  echo "2" > "$FASE_FILE"
  chown $REAL_USER:$REAL_USER "$LOG_FILE" "$FASE_FILE"
  
  # Registrar relanzamiento automático en el autostart para la Fase 2
  sudo -u $REAL_USER mkdir -p $USER_HOME/.config/autostart
  sudo -u $REAL_USER cat << EOF > $USER_HOME/.config/autostart/postinstall_fase2.desktop
[Desktop Entry]
Type=Application
Name=Fedora Postinstall Fase 2
Exec=sudo $USER_HOME/fedora-postinstall.sh
Terminal=true
X-GNOME-Autostart-enabled=true
EOF

  # Copiar el script actual a la carpeta de usuario para que la Fase 2 lo encuentre
  cp "$0" $USER_HOME/fedora-postinstall.sh
  chmod +x $USER_HOME/fedora-postinstall.sh

  echo "=============================================================================="
  echo " FASE 1 TERMINADA. Se requiere reiniciar el sistema para aplicar los cambios."
  echo " Al iniciar sesión, se abrirá una terminal automáticamente para la Fase 2."
  echo " Reiniciando en 5 segundos..."
  echo "=============================================================================="
  sleep 5
  reboot

else
  # ----------------------------------------------------------------------------
  # FASE 2: INSTALACIÓN DE SOFTWARE (TRAS EL REINICIO COMPLETO)
  # ----------------------------------------------------------------------------
  echo "=== INICIANDO FASE 2: Instalación de Software y Limpieza ==="
  
  # Eliminar el lanzador de la fase 2 para que no se vuelva a repetir
  rm -f $USER_HOME/.config/autostart/postinstall_fase2.desktop

  echo "Esperando 10 segundos a que la red esté completamente activa..."
  sleep 10

  echo "=== 10. Configurando el Firewall (KDE Connect y mDNS) ==="
  systemctl enable --now firewalld
  firewall-cmd --permanent --add-service=kdeconnect
  firewall-cmd --reload
  log_status $? "Configuración del Firewall"

  echo "=== 11. Configurando Temas para Aplicaciones Flatpak ==="
  flatpak override --system --filesystem=$USER_HOME/.themes
  flatpak override --system --env=GTK_THEME=my-theme
  flatpak override --system --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro --filesystem=/usr/share/themes:ro
  log_status $? "Overrides de temas para Flatpak"

  echo "=== 12. Instalando Programas del Sistema (DNF) ==="
  dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  dnf install -y tailscale steam kdeconnect
  systemctl enable --now tailscaled
  log_status $? "Instalación de programas DNF (Tailscale, Steam, KDE Connect)"

  echo "=== 13. Instalando Aplicaciones Flatpak ==="
  flatpak install -y flathub com.discordapp.Discord \
                              com.github.tchx84.Flatseal \
                              io.github.marcomotta.Warehouse \
                              io.github.fushandzhiguan.Bazaar \
                              org.telegram.desktop
  log_status $? "Instalación de aplicaciones Flatpak"

  echo "=== 14. Configurando aplicaciones en Inicio Automático (Minimizadas) ==="
  sudo -u $REAL_USER mkdir -p $USER_HOME/.config/autostart

  sudo -u $REAL_USER cat << 'EOF' > $USER_HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop
[Desktop Entry]
Type=Application
Name=KDE Connect Indicator
Exec=kdeconnect-indicator
Icon=kdeconnect
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

  sudo -u $REAL_USER cat << 'EOF' > $USER_HOME/.config/autostart/com.discordapp.Discord.desktop
[Desktop Entry]
Type=Application
Name=Discord
Exec=flatpak run com.discordapp.Discord --start-minimized
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

  sudo -u $REAL_USER cat << 'EOF' > $USER_HOME/.config/autostart/org.telegram.desktop.desktop
[Desktop Entry]
Type=Application
Name=Telegram
Exec=flatpak run org.telegram.desktop -startintray
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  log_status $? "Configuración de inicio automático minimizado"

  echo "=== 15. Optimizando Tiempos de Arranque Final ==="
  systemctl disable NetworkManager-wait-online.service
  systemctl enable fstrim.timer
  log_status $? "Optimización de arranque final y fstrim"

  echo "=== 16. Limpiando archivos temporales y caché ==="
  dnf clean all
  flatpak uninstall --unused -y
  log_status $? "Limpieza del sistema"

  # Limpieza de archivos de fase
  rm -f "$FASE_FILE"
  rm -f "$USER_HOME/fedora-postinstall.sh"

  echo "=== 17. Generando pantalla de reporte final ==="
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
Exec=$SCRIPT_LOG_VIEWER
Terminal=true
X-GNOME-Autostart-enabled=true
EOF

  echo "--------------------------------------------" >> "$LOG_FILE"
  echo "Proceso finalizado por completo con éxito." >> "$LOG_FILE"
  chown $REAL_USER:$REAL_USER "$LOG_FILE"

  echo "=============================================================================="
  echo " ¡FASE 2 COMPLETADA! El sistema se configuró e instaló por completo."
  echo " Presiona ENTRAR para cerrar y disfrutar de tu sistema."
  echo "=============================================================================="
  read -p ""
fi
