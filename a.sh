#!/bin/bash
set -euo pipefail

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
    
    if [ -d /sys/block/nvme* ] 2>/dev/null || [ -d /sys/block/sd* ] 2>/dev/null; then
        SSD=true
    else
        SSD=false
    fi
}

setup_sources() {
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    sudo sed -i '/Color/a ILoveCandy' /etc/pacman.conf
    sudo sed -i '/^ParallelDownloads/d' /etc/pacman.conf
    sudo sed -i '/ILoveCandy/a ParallelDownloads = 15' /etc/pacman.conf
    sudo sed -i 's/^timeout [0-9]*/timeout 2/' /boot/loader/loader.conf
    
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst" \
        "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    
    sudo pacman -Syu --noconfirm
}

install_packages() {
    case "$CPU" in
        intel) sudo pacman -S --noconfirm intel-ucode ;;
        amd) sudo pacman -S --noconfirm amd-ucode ;;
    esac
    
    case "$GPU" in
        intel) sudo pacman -S --noconfirm vulkan-intel ;;
        amd) sudo pacman -S --noconfirm vulkan-radeon ;;
        nvidia) sudo pacman -S --noconfirm nvidia-open ;;
    esac
    
    sudo pacman -S --noconfirm fastfetch msedit 7zip gamemode arch-update
    
    if [ "$SSD" = true ]; then
        sudo systemctl enable fstrim.timer
    fi
}

install_cosmic() {
    sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-monitor cosmic-store cosmic-text-editor cosmic-player cosmic-wallpapers xdg-desktop-portal-gtk xdg-user-dirs
    sudo systemctl enable cosmic-greeter
}

setup_system() {
    sudo ufw reload
    sudo ufw allow 53317/udp
    sudo ufw allow 53317/tcp
    
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
}

main() {
    detect_system
    setup_sources
    install_packages
    install_cosmic
    setup_system
    echo ""
    echo -e '\e[32mInstalação concluída!\e[0m'
}

main
