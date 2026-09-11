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
}

setup_sources() {
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    sudo sed -i '/Color/a ILoveCandy' /etc/pacman.conf
    sudo sed -i '/^ParallelDownloads/d' /etc/pacman.conf
    sudo sed -i '/ILoveCandy/a ParallelDownloads = 15' /etc/pacman.conf
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
    
    sudo pacman -S --noconfirm flatpak fastfetch msedit 7zip
}

setup_system() {
    sudo ufw reload
    sudo ufw allow 53317/udp
    sudo ufw allow 53317/tcp
    
    sudo pacman -S --noconfirm gamemode fwupd reflector power-profiles-daemon earlyoom
    sudo systemctl enable fstrim.timer fwupd-refresh.timer reflector.timer power-profiles-daemon earlyoom
    sudo usermod -aG gamemode "$USER"
    
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
    
    sudo tee /etc/xdg/reflector/reflector.conf > /dev/null <<EOF
--save /etc/pacman.d/mirrorlist
--latest 10
--sort rate
--age 12
--protocol https
--country "Brazil,United States"
EOF
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

orphans=$(pacman -Qdtq 2>/dev/null || true)
if [ -n "$orphans" ]; then
    sudo pacman -Rns $orphans --noconfirm || true
fi

sudo pacman -Syu --noconfirm || exit 1

sudo pacman -Sc --noconfirm || true

if command -v flatpak >/dev/null 2>&1; then
    flatpak uninstall --unused --delete-data -y || true
    flatpak update -y || true
fi

if [ -n "$(find /etc -name '*.pacnew' -o -name '*.pacsave' 2>/dev/null)" ]; then
    sudo pacdiff --noconfirm || true
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
    setup_system
    install_desktop
    install_updater
}

main
