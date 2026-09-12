#!/bin/bash
set -euo pipefail

if [ ! -f /etc/arch-release ]; then
    echo -e '\e[31mEste script é apenas para Arch Linux!\e[0m'
    exit 1
fi

detect_system() {
    local cpu_info=$(cat /proc/cpuinfo 2>/dev/null)
    if echo "$cpu_info" | grep -qi "intel"; then
        CPU="intel"
    elif echo "$cpu_info" | grep -qi "amd"; then
        CPU="amd"
    else
        CPU="intel"
    fi
    
    local gpu_info=$(lspci -nn 2>/dev/null | grep -E "VGA|3D|Display" | head -1)
    if echo "$gpu_info" | grep -qi "nvidia"; then
        GPU="nvidia"
    elif echo "$gpu_info" | grep -qi "amd\|radeon"; then
        GPU="amd"
    elif echo "$gpu_info" | grep -qi "intel"; then
        GPU="intel"
    else
        GPU="nvidia"
    fi
}

setup_sources() {
    sudo sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf
    sudo sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 15/' /etc/pacman.conf
    sudo sed -i 's/^timeout [0-9]*/timeout 2/' /boot/loader/loader.conf
    
    sudo pacman -Syu --noconfirm
}

install_base() {
    case "$CPU" in
        intel) sudo pacman -S --noconfirm intel-ucode ;;
        amd) sudo pacman -S --noconfirm amd-ucode ;;
    esac
    
    case "$GPU" in
        intel) sudo pacman -S --noconfirm vulkan-intel ;;
        amd) sudo pacman -S --noconfirm vulkan-radeon ;;
        nvidia) sudo pacman -S --noconfirm nvidia-open ;;
    esac
    
    sudo pacman -S --noconfirm flatpak fastfetch msedit 7zip gamemode
}

setup_reflector() {
    sudo pacman -S --noconfirm reflector
    sudo systemctl enable reflector.timer
    
    sudo sed -i 's|^#--save .*|--save /etc/pacman.d/mirrorlist|' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#--protocol .*/--protocol https/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#--country .*/--country "Brazil,United States"/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#--latest .*/--latest 10\n--age 12/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^#--sort .*/--sort rate/' /etc/xdg/reflector/reflector.conf
}

setup_system() {
    sudo ufw reload
    sudo ufw allow 53317/udp
    sudo ufw allow 53317/tcp
    
    sudo pacman -S --noconfirm fwupd power-profiles-daemon
    sudo systemctl enable fstrim.timer fwupd-refresh.timer power-profiles-daemon
    
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
}

setup_oomd() {
    sudo mkdir -p /etc/systemd/system/user@.service.d
    sudo tee /etc/systemd/system/user@.service.d/override.conf > /dev/null <<EOF
[Service]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=50%
EOF
    
    sudo mkdir -p /etc/systemd/oomd.conf.d
    sudo tee /etc/systemd/oomd.conf.d/override.conf > /dev/null <<EOF
[OOM]
DefaultMemoryPressureDurationSec=20s
EOF
    
    sudo systemctl enable --now systemd-oomd
}

install_desktop() {
    sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-monitor cosmic-store cosmic-text-editor cosmic-player cosmic-wallpapers xdg-user-dirs xdg-desktop-portal-gtk
    sudo systemctl enable cosmic-greeter
}

install_updater() {
    sudo tee /usr/local/bin/system-update > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

if ! command -v pacman >/dev/null 2>&1; then
    exit 1
fi

if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
    exit 1
fi

if ! id -nG "$USER" | grep -qw gamemode; then
    sudo usermod -aG gamemode "$USER"
fi

sudo pacman -Syu --noconfirm || exit 1

orphans=$(pacman -Qdtq 2>/dev/null)
if [ -n "$orphans" ]; then
    sudo pacman -Rnsu $orphans --noconfirm
fi

sudo pacman -Sc --noconfirm

if command -v flatpak >/dev/null 2>&1; then
    flatpak uninstall --unused --delete-data -y
    flatpak update -y
fi

echo ""
echo "Sistema atualizado com sucesso, pressione enter para sair"
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
    detect_system
    setup_sources
    install_base
    setup_reflector
    setup_system
    setup_oomd
    install_desktop
    install_updater
    
    echo ""
    echo -e '\e[32mInstalação concluída!\e[0m'
}

main
