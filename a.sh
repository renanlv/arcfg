#!/bin/bash
set -euo pipefail
STATE_DIR="/tmp/arch_install_state"
mkdir -p "$STATE_DIR"

if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; BOLD=''; NC=''
fi

clear_screen() { clear; }

show_section() {
    echo "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
    echo "${GREEN}► $1${NC}"
    echo "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

show_option() {
    echo "  ${CYAN}$1${NC}) $2"
}

detect_distro() {
    if [ -f /etc/arch-release ]; then
        echo "arch" > "$STATE_DIR/distro"
    else
        echo "${RED}Este script é apenas para Arch Linux!${NC}"
        exit 1
    fi
}

detect_hardware() {
    local cpu_info=$(cat /proc/cpuinfo 2>/dev/null)
    if echo "$cpu_info" | grep -qi "intel"; then
        echo "intel" > "$STATE_DIR/cpu"
    elif echo "$cpu_info" | grep -qi "amd"; then
        echo "amd" > "$STATE_DIR/cpu"
    else
        echo "intel" > "$STATE_DIR/cpu"
    fi
    
    local gpu_info=$(lspci -nn 2>/dev/null | grep -E "VGA|3D|Display" | head -1)
    if echo "$gpu_info" | grep -qi "nvidia"; then
        echo "nvidia" > "$STATE_DIR/gpu_driver"
    elif echo "$gpu_info" | grep -qi "amd\|radeon"; then
        echo "amd" > "$STATE_DIR/gpu_driver"
    elif echo "$gpu_info" | grep -qi "intel"; then
        echo "intel" > "$STATE_DIR/gpu_driver"
    else
        echo "nvidia" > "$STATE_DIR/gpu_driver"
    fi
    
    local brand="gigabyte"
    if [ -f /sys/class/dmi/id/board_vendor ]; then
        brand=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)
    fi
    if [ -z "$brand" ] || [ "$brand" == "Unknown" ] || [ "$brand" == "To be filled by O.E.M." ]; then
        if [ -f /sys/class/dmi/id/sys_vendor ]; then
            brand=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
        fi
    fi
    case "$brand" in
        *"ASUS"*|*"Asus"*) echo "asus" > "$STATE_DIR/motherboard_brand" ;;
        *"Gigabyte"*|*"GIGABYTE"*) echo "gigabyte" > "$STATE_DIR/motherboard_brand" ;;
        *"MSI"*|*"Micro-Star"*) echo "msi" > "$STATE_DIR/motherboard_brand" ;;
        *"Acer"*) echo "acer" > "$STATE_DIR/motherboard_brand" ;;
        *"Dell"*) echo "dell" > "$STATE_DIR/motherboard_brand" ;;
        *"HP"*|*"Hewlett-Packard"*) echo "hp" > "$STATE_DIR/motherboard_brand" ;;
        *"Lenovo"*) echo "lenovo" > "$STATE_DIR/motherboard_brand" ;;
        *) echo "gigabyte" > "$STATE_DIR/motherboard_brand" ;;
    esac
}

detect_systemd_boot() {
    local has_systemd_boot=false
    local esp_path=""
    
    if mount | grep -q "/boot/efi "; then
        esp_path="/boot/efi"
    elif mount | grep -q "/boot "; then
        esp_path="/boot"
    elif [ -d /boot/EFI ]; then
        esp_path="/boot"
    elif [ -d /boot/efi/EFI ]; then
        esp_path="/boot/efi"
    fi
    
    if [ -n "$esp_path" ]; then
        if [ -f "${esp_path}/EFI/systemd/systemd-bootx64.efi" ] || [ -f "${esp_path}/loader/loader.conf" ] || [ -f "/boot/loader/loader.conf" ]; then
            has_systemd_boot=true
        fi
    fi
    
    if [ "$has_systemd_boot" = false ] && command -v bootctl &>/dev/null; then
        if sudo bootctl status 2>/dev/null | grep -q "systemd-boot"; then
            has_systemd_boot=true
            if [ -f "/boot/loader/loader.conf" ]; then
                esp_path="/boot"
            elif [ -f "/boot/efi/loader/loader.conf" ]; then
                esp_path="/boot/efi"
            fi
        fi
    fi
    
    if [ "$has_systemd_boot" = true ] && [ -n "$esp_path" ]; then
        echo "true" > "$STATE_DIR/has_systemd_boot"
        echo "$esp_path" > "$STATE_DIR/esp_path"
    else
        echo "false" > "$STATE_DIR/has_systemd_boot"
    fi
}

select_desktop() {
    clear_screen
    show_section "AMBIENTE DESKTOP"
    
    show_option "1" "GNOME"
    show_option "2" "KDE Plasma"
    show_option "3" "COSMIC"
    echo ""
    read -p "Opção [1-3] (Enter para GNOME): " de_opt
    
    case "$de_opt" in
        1|"") echo "gnome" > "$STATE_DIR/desktop" ;;
        2) echo "kde" > "$STATE_DIR/desktop" ;;
        3) echo "cosmic" > "$STATE_DIR/desktop" ;;
        *) echo "${RED}Opção inválida.${NC}"
           sleep 1
           select_desktop
           return
    esac
    sleep 1
}

setup_pacman() {
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    sudo sed -i '/Color/a ILoveCandy' /etc/pacman.conf
    sudo sed -i '/^ParallelDownloads/d' /etc/pacman.conf
    sudo sed -i '/ILoveCandy/a ParallelDownloads = 15' /etc/pacman.conf
    
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst" \
        "https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst"
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    
    sudo pacman -Syu --noconfirm
}

setup_extra_environment() {
    sudo pacman -S --noconfirm fwupd flatpak gamemode
    sudo systemctl enable fwupd-refresh.timer
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

install_microcode_drivers() {
    local cpu=$(cat "$STATE_DIR/cpu")
    case "$cpu" in
        intel) sudo pacman -S --noconfirm intel-ucode ;;
        amd) sudo pacman -S --noconfirm amd-ucode ;;
    esac
    
    local gpu=$(cat "$STATE_DIR/gpu_driver")
    case "$gpu" in
        intel) sudo pacman -S --noconfirm vulkan-intel ;;
        amd) sudo pacman -S --noconfirm vulkan-radeon ;;
        nvidia) sudo pacman -S --noconfirm nvidia-open ;;
    esac
}

install_base_packages() {
    sudo pacman -S --noconfirm git 7zip aria2 tealdeer fastfetch msedit arch-update
}

install_desktop() {
    local desktop=$(cat "$STATE_DIR/desktop")
    
    case "$desktop" in
        gnome)
            sudo pacman -S --noconfirm gnome-initial-setup gnome-console gnome-system-monitor gnome-disk-utility gnome-keyring gnome-software gnome-backgrounds
            sudo systemctl enable gdm
            ;;
        kde)
            sudo pacman -S --noconfirm plasma-meta konsole dolphin dolphin-plugins partitionmanager filelight ark 
            sudo systemctl enable plasmalogin
            ;;
        cosmic)
            sudo pacman -S --noconfirm cosmic-session cosmic-terminal cosmic-files cosmic-monitor cosmic-store cosmic-wallpapers xdg-desktop-portal-gtk xdg-user-dirs
            sudo systemctl enable cosmic-greeter
            ;;
    esac
}

configure_firewall() {
    sudo ufw reload
    sudo ufw allow 53317/udp
    sudo ufw allow 53317/tcp
}

configure_performance() {
    sudo systemctl enable fstrim.timer
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/performance.conf > /dev/null <<EOF
MESA_SHADER_CACHE_MAX_SIZE=12G
__GL_SHADER_DISK_CACHE_SIZE=12000000000
EOF
}

configure_boot() {
    local has_systemd_boot=$(cat "$STATE_DIR/has_systemd_boot")
    [ "$has_systemd_boot" != "true" ] && return 0
    
    local loader_conf="/boot/loader/loader.conf"
    
    if [ -f "$loader_conf" ]; then
        if grep -q "^timeout" "$loader_conf"; then
            sudo sed -i 's/^timeout [0-9]*/timeout 2/' "$loader_conf"
        else
            echo "timeout 2" | sudo tee -a "$loader_conf" > /dev/null
        fi
    else
        echo "timeout 2" | sudo tee "$loader_conf" > /dev/null
    fi
    
    local motherboard_brand=$(cat "$STATE_DIR/motherboard_brand")
    
    if ! command -v sbctl &>/dev/null; then
        sudo pacman -S --noconfirm sbctl
    fi
    
    if ! sudo sbctl status 2>/dev/null | grep -q "Setup Mode.*Enabled"; then
        return 0
    fi
    
    if [ ! -f /etc/secureboot/keys/db/db.key ] && [ ! -f /usr/share/secureboot/keys/db/db.key ]; then
        sudo sbctl create-keys
    fi
    
    if ! sudo sbctl status | grep -q "Vendor Keys:.*microsoft"; then
        if [[ "$motherboard_brand" == "asus" ]] || [[ "$motherboard_brand" == "gigabyte" ]]; then
            sudo sbctl enroll-keys --microsoft
        else
            sudo sbctl enroll-keys --microsoft --firmware-builtin
        fi
    fi
    
    [ -f /boot/vmlinuz-linux ] && sudo sbctl sign -s /boot/vmlinuz-linux || true
    [ -f /boot/vmlinuz-linux-lts ] && sudo sbctl sign -s /boot/vmlinuz-linux-lts || true
    
    if [ -f /boot/EFI/Linux/arch-linux.efi ]; then
        sudo sbctl sign -s /boot/EFI/Linux/arch-linux.efi || true
    elif [ -f /boot/efi/Linux/arch-linux.efi ]; then
        sudo sbctl sign -s /boot/efi/Linux/arch-linux.efi || true
    else
        sudo mkdir -p /boot/EFI/Linux
        sudo mkinitcpio -P
        [ -f /boot/EFI/Linux/arch-linux.efi ] && sudo sbctl sign -s /boot/EFI/Linux/arch-linux.efi || true
    fi
    
    local esp_path=$(cat "$STATE_DIR/esp_path")
    
    [ -f "${esp_path}/EFI/systemd/systemd-bootx64.efi" ] && sudo sbctl sign -s "${esp_path}/EFI/systemd/systemd-bootx64.efi" || true
    [ -f /usr/lib/systemd/boot/efi/systemd-bootx64.efi ] && sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi || true
    [ -f "${esp_path}/EFI/BOOT/BOOTX64.EFI" ] && sudo sbctl sign -s "${esp_path}/EFI/BOOT/BOOTX64.EFI" || true
    [ -f /usr/lib/fwupd/efi/fwupdx64.efi ] && sudo sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi || true
}

main() {
    detect_distro
    detect_hardware
    detect_systemd_boot
    
    select_desktop
    setup_pacman
    setup_extra_environment
    
    install_microcode_drivers
    install_base_packages
    install_desktop
    
    configure_firewall
    configure_performance
    configure_boot
    
    echo ""
    echo "${GREEN}Instalação concluída!${NC}"
    echo "${YELLOW}Reinicie o sistema para concluir a instalação.${NC}"
}

main
