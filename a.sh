#!/bin/bash
set -euo pipefail

setup_system() {
    if [ ! -f /etc/arch-release ]; then
        echo "Este script é apenas para Arch Linux!"
        exit 1
    fi
    
    sudo sed -i 's/^#*\s*Color.*/Color\nILoveCandy/' /etc/pacman.conf
    sudo sed -i 's/^#*\s*ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^#*\s*timeout.*/timeout 2/' /boot/loader/loader.conf
    sudo pacman -Syu --noconfirm
    
    sudo ufw reload
    sudo ufw allow 53317/udp
    sudo ufw allow 53317/tcp
    
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
}

install_drivers() {
    if grep -qi "amd" /proc/cpuinfo; then
        sudo pacman -S --noconfirm amd-ucode
    else
        sudo pacman -S --noconfirm intel-ucode
    fi
    
    if lspci -nn | grep -E "VGA|3D|Display" | grep -qi "amd\|radeon"; then
        sudo pacman -S --noconfirm vulkan-radeon
    elif lspci -nn | grep -E "VGA|3D|Display" | grep -qi "intel"; then
        sudo pacman -S --noconfirm vulkan-intel
    else
        sudo pacman -S --noconfirm nvidia-open
    fi
}

install_base() {
    sudo pacman -S --noconfirm fastfetch msedit flatpak fwupd reflector power-profiles-daemon
    sudo systemctl enable fstrim.timer reflector.timer power-profiles-daemon
    
    sudo sed -i 's|^#*\s*--save.*|--save /etc/pacman.d/mirrorlist|' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--protocol.*/--protocol https/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--country.*/--country "Brazil,United States"/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--latest.*/--latest 10/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--sort.*/--sort rate/' /etc/xdg/reflector/reflector.conf
}

install_desktop() {
    read -rp "Instalar COSMIC desktop? [S/n]: " choice; if [[ "${choice,,}" == "n" ]]; then
        sudo pacman -S --noconfirm plasma-meta konsole dolphin partitionmanager filelight kate kcalc gwenview haruna ark
        sudo systemctl enable plasmalogin
    else
        sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-monitor cosmic-store cosmic-text-editor cosmic-player cosmic-wallpapers xdg-user-dirs xdg-desktop-portal-gtk
        sudo systemctl enable cosmic-greeter
    fi
}

setup_updater() {
    sudo tee /usr/local/bin/system-update > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

sudo pacman -Syu --noconfirm
orphans=$(pacman -Qdtq 2>/dev/null || true)
if [ -n "$orphans" ]; then
    sudo pacman -Rnsu $orphans --noconfirm
fi
sudo pacman -Sc --noconfirm

echo "Sistema atualizado com sucesso, pressione enter para sair"
read -r
EOF

    sudo chmod +x /usr/local/bin/system-update
    sudo tee /usr/share/applications/system-update.desktop > /dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=System Update
Exec=/usr/local/bin/system-update
Icon=system-software-update
Terminal=true
Categories=System;
EOF
}

main() {
    setup_system
    install_drivers
    install_base
    install_desktop
    setup_updater
    echo "Instalação concluída!"
}

main
