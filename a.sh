#!/bin/bash
set -euo pipefail

detect_system() {
    if [ ! -f /etc/arch-release ]; then
        echo "Este script é apenas para Arch Linux!"
        exit 1
    fi
    
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

select_desktop() {
    clear
    echo "Escolha o ambiente desktop:"
    echo "1) COSMIC"
    echo "2) KDE Plasma"
    echo "3) GNOME"
    read -p "Opção [1-3] (Enter para COSMIC): " option
    
    case "$option" in
        2) DESKTOP="kde" ;;
        3) DESKTOP="gnome" ;;
        *) DESKTOP="cosmic" ;;
    esac
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

setup_reflector() {
    sudo pacman -S --noconfirm reflector
    sudo systemctl enable reflector.timer
    
    sudo tee /etc/xdg/reflector/reflector.conf > /dev/null <<EOF
--save /etc/pacman.d/mirrorlist
--latest 10
--sort rate
--age 12
--protocol https
--country "Brazil,United States"
EOF
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
    
    sudo mkdir -p /etc/systemd/system/-.slice.d
    sudo tee /etc/systemd/system/-.slice.d/override.conf > /dev/null <<EOF
[Slice]
ManagedOOMSwap=kill
EOF
    
    sudo sed -i 's/^#DefaultMemoryAccounting=.*/DefaultMemoryAccounting=yes/' /etc/systemd/system.conf
    
    sudo tee /etc/systemd/oomd.conf > /dev/null <<EOF
[OOM]
SwapUsedLimit=90%
DefaultMemoryPressureDurationSec=20s
EOF
    
    sudo systemctl enable --now systemd-oomd
}

install_desktop() {
    case "$DESKTOP" in
        kde)
            sudo pacman -S --noconfirm plasma-meta konsole dolphin partitionmanager filelight kate kcalc gwenview haruna ark xdg-desktop-portal-kde xdg-user-dirs
            sudo systemctl enable plasmalogin
            ;;
        gnome)
            sudo pacman -S --noconfirm gnome gnome-tweaks gnome-shell-extensions xdg-desktop-portal-gnome xdg-user-dirs
            sudo systemctl enable gdm
            ;;
        cosmic)
            sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-monitor cosmic-store cosmic-text-editor cosmic-player cosmic-wallpapers xdg-user-dirs xdg-desktop-portal-gtk
            sudo systemctl enable cosmic-greeter
            ;;
    esac
}

install_maintenance() {
    sudo tee /usr/local/bin/system-maintenance > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail

update_system() {
    if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
        echo "Sem conexão com a internet."
        read -p "Pressione enter para voltar..."
        return
    fi
    
    sudo pacman -Syu --noconfirm
    
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
    echo "Sistema atualizado com sucesso, pressione enter para voltar"
    read -r
}

install_software() {
    while true; do
        clear
        echo "Instalar/Remover programas:"
        
        if pacman -Q gamemode >/dev/null 2>&1; then
            echo "1) gamemode [instalado]"
        else
            echo "1) gamemode [não instalado]"
        fi
        
        if pacman -Q fish >/dev/null 2>&1; then
            echo "2) fish [instalado]"
        else
            echo "2) fish [não instalado]"
        fi
        
        echo "0) Voltar"
        read -p "Opção: " opt
        
        case "$opt" in
            1)
                if pacman -Q gamemode >/dev/null 2>&1; then
                    sudo pacman -Rnsu --noconfirm gamemode
                else
                    sudo pacman -S --noconfirm gamemode
                    sudo usermod -aG gamemode "$USER"
                fi
                ;;
            2)
                if pacman -Q fish >/dev/null 2>&1; then
                    sudo pacman -Rnsu --noconfirm fish
                    sudo chsh -s /bin/bash "$USER"
                else
                    sudo pacman -S --noconfirm fish
                    sudo chsh -s /usr/bin/fish "$USER"
                    fish -c "set -U fish_greeting" >/dev/null 2>&1
                fi
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

while true; do
    clear
    echo "Manutenção do Sistema"
    echo ""
    echo "1) Atualizar sistema"
    echo "2) Instalar programas"
    echo "0) Sair"
    read -p "Opção: " opt
    
    case "$opt" in
        1) update_system ;;
        2) install_software ;;
        0) exit 0 ;;
        *) ;;
    esac
done
EOF

    sudo chmod +x /usr/local/bin/system-maintenance

    sudo tee /usr/share/applications/system-maintenance.desktop > /dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=System Maintenance
Comment=Atualiza o sistema e instala programas
Exec=/usr/local/bin/system-maintenance
Icon=system-software-update
Terminal=true
Categories=System;
EOF
}

main() {
    detect_system
    select_desktop
    setup_sources
    install_base
    setup_reflector
    setup_system
    setup_oomd
    install_desktop
    install_maintenance
    
    echo ""
    echo "Instalação concluída!"
}

main
