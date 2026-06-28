#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 2: INSTALACIÓN DE APLICACIONES DE USUARIO Y CONFIGURACIÓN DE INICIO
# ==============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta este script usando sudo: sudo $0"
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
LOG_FILE="$USER_HOME/fedora_apps_install.log"

set +e

log_status() {
    if [ $1 -eq 0 ]; then
        echo "✅ SUCESO: $2" >> "$LOG_FILE"
    else
        echo "❌ FALLÓ: $2" >> "$LOG_FILE"
    fi
}

echo "=== INICIANDO INSTALACIÓN DE APLICACIONES DE USUARIO ==="
echo "=== REPORTE DE APLICACIONES ===" > "$LOG_FILE"
echo "Fecha: $(date)" >> "$LOG_FILE"
echo "Usuario: $REAL_USER" >> "$LOG_FILE"
echo "--------------------------------------------" >> "$LOG_FILE"

echo "=== 1. Configurando Firewall para KDE Connect ==="
if /usr/bin/rpm -q firewalld &>/dev/null; then
    firewall-cmd --permanent --add-service=kdeconnect
    firewall-cmd --reload
fi
log_status $? "Configuración de Firewall"

echo "=== 2. Instalando Aplicaciones del Sistema (DNF) ==="
/usr/bin/dnf install -y --setopt=install_weak_deps=False steam kde-connect firefox
log_status $? "Instalación de Steam, KDE Connect y Firefox"

echo "=== 3. Configurando carpetas de usuario e Inicio Automático ==="
sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.config/autostart"

cat << 'EOF' | sudo -u "$REAL_USER" tee "$USER_HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop" > /dev/null
[Desktop Entry]
Type=Application
Name=KDE Connect Indicator
Exec=kdeconnect-indicator
Icon=kdeconnect
Terminal=false
Categories=Network;
EOF

cat << 'EOF' | sudo -u "$REAL_USER" tee "$USER_HOME/.config/autostart/org.telegram.desktop.desktop" > /dev/null
[Desktop Entry]
Type=Application
Name=Telegram
Exec=sh -c "sleep 20 && /usr/bin/flatpak run org.telegram.desktop -startintray"
Icon=telegram
Terminal=false
Categories=Network;InstantMessaging;
EOF
log_status $? "Configuración de inicio automático"

echo "=== 4. Instalando Aplicaciones Flatpak (Pesadas) ==="
/usr/bin/flatpak update --appstream -y
/usr/bin/flatpak install --system -y flathub \
    com.discordapp.Discord \
    com.vysp3r.ProtonPlus \
    com.github.tchx84.Flatseal \
    io.github.flattool.Warehouse \
    org.telegram.desktop \
    io.github.kolunmi.Bazaar
log_status $? "Instalación de Flatpaks"

echo "=== 5. Limpieza final de paquetes y cachés ==="
/usr/bin/flatpak uninstall --unused -y
/usr/bin/update-desktop-database /var/lib/flatpak/exports/share/applications &>/dev/null

echo "--------------------------------------------" >> "$LOG_FILE"
echo "Todas las aplicaciones de usuario han sido instaladas con éxito." >> "$LOG_FILE"
/usr/bin/chown "$REAL_USER":"$REAL_USER" "$LOG_FILE"

echo "=============================================================================="
echo " ¡PROCESO FINALIZADO CON ÉXITO!"
echo " Las aplicaciones de usuario y accesos directos están listos en tu entorno."
echo "=============================================================================="