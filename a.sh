#!/bin/bash
set -euo pipefail
RED='\e[31m'
GREEN='\e[32m'
NC='\e[0m'

if [ ! -f /etc/arch-release ]; then
    echo -e "${RED}Este script é apenas para Arch Linux!${NC}"
    exit 1
fi

setup_system() {
    sudo sed -i 's/^#*\s*Color/Color\nILoveCandy/' /etc/pacman.conf
    sudo sed -i 's/^#*\s*ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^timeout [0-9]*/timeout 2/' /boot/loader/loader.conf
    
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

install_base() {
    sudo pacman -S --noconfirm intel-ucode nvidia-open fastfetch msedit 7zip
}

setup_base() {
    sudo pacman -S --noconfirm flatpak fwupd reflector earlyoom power-profiles-daemon
    sudo systemctl enable fstrim.timer fwupd-refresh.timer reflector.timer earlyoom power-profiles-daemon
    
    sudo sed -i 's|^#*\s*--save .*|--save /etc/pacman.d/mirrorlist|' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--protocol .*/--protocol https/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--country .*/--country "Brazil,United States"/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--latest .*/--latest 10/' /etc/xdg/reflector/reflector.conf
    sudo sed -i '/^--latest/a --age 12' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#*\s*--sort .*/--sort rate/' /etc/xdg/reflector/reflector.conf
}

install_desktop() {
    sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-monitor cosmic-store cosmic-text-editor cosmic-player cosmic-wallpapers xdg-user-dirs xdg-desktop-portal-gtk
    sudo systemctl enable cosmic-greeter
}

setup_updater() {
    sudo tee /usr/local/bin/system-update > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
GREEN='\e[32m'
NC='\e[0m'

if [ -n "$(pacman -Qu 2>/dev/null)" ]; then
    sudo pacman -Syu --noconfirm
    sudo pacman -Fy --noconfirm
    orphans=$(pacman -Qdtq 2>/dev/null)
    if [ -n "$orphans" ]; then
        sudo pacman -Rnsu $orphans --noconfirm
    fi
    sudo pacman -Sc --noconfirm
    flatpak uninstall --unused --delete-data -y
fi

echo -e "${GREEN}Sistema atualizado com sucesso, pressione enter para sair${NC}"
read -r
EOF

    sudo chmod +x /usr/local/bin/system-update
    sudo tee /usr/share/applications/system-update.desktop > /dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=System Update
Comment=Atualiza o sistema
Exec=/usr/local/bin/system-update
Icon=system-software-update
Terminal=true
Categories=System;
EOF
}

main() {
    setup_system
    install_base
    setup_base
    install_desktop
    setup_updater
    echo -e "${GREEN}Instalação concluída!${NC}"
}

main
