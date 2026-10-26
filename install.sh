#!/usr/bin/env bash

# ==============================================================================
# hypr-dotfiles Intelligent Installer
# Dynamic & Modular Hyprland Desktop Environment for Arch Linux
# Supports: Fresh Minimal Arch, Existing DE Switching/Coexistence, & Repair Mode
# ==============================================================================

set -euo pipefail

# Visual styling
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_BLUE="\033[1;34m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"
C_CYAN="\033[1;36m"
C_MAGENTA="\033[1;35m"
C_WHITE="\033[1;37m"

info()    { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$1"; }
success() { printf "${C_GREEN}[DONE]${C_RESET} %s\n" "$1"; }
warn()    { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1"; }
error()   { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1" >&2; }
step()    { printf "\n${C_CYAN}::${C_BOLD} %s${C_RESET}\n" "$1"; }

# ------------------------------------------------------------------------------
# 1. Pipe / One-Liner Detection & Self-Bootstrap
# ------------------------------------------------------------------------------
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

if [[ -z "$SCRIPT_DIR" || ! -d "${SCRIPT_DIR}/.config" || ! -f "${SCRIPT_DIR}/packages-pacman.txt" ]]; then
    printf "${C_BLUE}[INFO]${C_RESET} Running via one-liner/pipe. Bootstrapping repository to temporary directory...\n"
    
    REPO_URL="${DOTS_REPO_URL:-https://github.com/DX4GREY/hypr-dotfiles.git}"
    TEMP_DIR="$(mktemp -d -t hypr-dotfiles-XXXXXX)"
    
    if ! command -v git >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm git
    fi
    
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR/hypr-dotfiles"
    cd "$TEMP_DIR/hypr-dotfiles"
    exec bash install.sh "$@"
fi

# ------------------------------------------------------------------------------
# 2. Interactive Input Helpers (Supports /dev/tty for piped curl)
# ------------------------------------------------------------------------------
NON_INTERACTIVE=0

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local response=""
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        echo "$default"
        return
    fi

    if [[ -t 0 ]]; then
        read -rp "$prompt" response 2>/dev/null || response="$default"
    elif [[ -e /dev/tty && -r /dev/tty ]]; then
        read -rp "$prompt" response < /dev/tty 2>/dev/null || response="$default"
    else
        response="$default"
    fi
    echo "${response:-$default}"
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local reply
    if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
        [[ "$default" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
    reply="$(prompt_input "$prompt " "$default")"
    [[ "$reply" =~ ^[Yy]$ ]] && return 0 || return 1
}

# ------------------------------------------------------------------------------
# 3. CLI Arguments Parsing
# ------------------------------------------------------------------------------
TARGET_MODE=""

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--non-interactive) NON_INTERACTIVE=1 ;;
        --fresh)                    TARGET_MODE="fresh" ;;
        --switch|--coexist)         TARGET_MODE="switch" ;;
        --repair)                   TARGET_MODE="repair" ;;
        --custom)                   TARGET_MODE="custom" ;;
        -h|--help)
            cat << EOF
hypr-dotfiles Intelligent Installer

Usage: ./install.sh [OPTIONS]

Options:
  -y, --non-interactive    Run without interactive prompts (uses recommended defaults)
      --fresh              Mode 1: Full fresh Arch install (packages, DM, GPU, configs)
      --switch             Mode 2: Switch / Coexist alongside existing DE
      --repair             Mode 3: Repair & reconfigure dotfiles, theme, and plugins
      --custom             Mode 4: Custom step-by-step interactive configuration
  -h, --help               Show this help message and exit
EOF
            exit 0
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 4. System Validation & Permission Check
# ------------------------------------------------------------------------------
clear 2>/dev/null || true

printf "${C_CYAN}%s${C_RESET}\n" "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
printf "${C_CYAN}┃${C_BOLD}${C_WHITE}           HYPR-DOTFILES INTELLIGENT INSTALLER              ${C_CYAN}┃${C_RESET}\n"
printf "${C_CYAN}┃${C_RESET}       Modern & Dynamic Hyprland Ecosystem for Arch Linux   ${C_CYAN}┃${C_RESET}\n"
printf "${C_CYAN}%s${C_RESET}\n\n" "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

if [[ "${EUID}" -eq 0 ]]; then
    error "Please do not execute this installer as root / sudo directly."
    error "Run as your normal user. The script will request sudo when required."
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    error "/etc/os-release not found. Cannot determine Linux distribution."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "arch" && "${ID_LIKE:-}" != *arch* ]]; then
    error "This installer is tailored strictly for Arch Linux or Arch-based distributions."
    error "Detected system: ${PRETTY_NAME:-unknown}"
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    error "'sudo' is required to manage system packages."
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    error "'pacman' was not found. Arch Linux base installation required."
    exit 1
fi

# Request sudo credentials early
info "Checking administrative privileges..."
if ! sudo -n true 2>/dev/null; then
    sudo -v
fi
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap 'kill "$SUDO_PID" 2>/dev/null || true' EXIT

# ------------------------------------------------------------------------------
# 5. Environment & Hardware Detection Dashboard
# ------------------------------------------------------------------------------
step "Analyzing System Architecture & Environment"

# Distribution
printf "  ${C_CYAN}-> Distribution:${C_RESET}    %s\n" "${PRETTY_NAME:-Arch Linux}"

# Detect Existing Desktop Environment
DETECTED_DE="None (Pure TTY / Minimal)"
if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
    DETECTED_DE="${XDG_CURRENT_DESKTOP}"
elif command -v gnome-shell >/dev/null 2>&1; then
    DETECTED_DE="GNOME Desktop"
elif command -v plasmashell >/dev/null 2>&1; then
    DETECTED_DE="KDE Plasma"
elif command -v xfce4-session >/dev/null 2>&1; then
    DETECTED_DE="XFCE Desktop"
elif command -v cinnamon >/dev/null 2>&1; then
    DETECTED_DE="Cinnamon"
fi
printf "  ${C_CYAN}-> Environment:${C_RESET}     %s\n" "$DETECTED_DE"

# Detect Active / Installed Display Manager
DETECTED_DM="None (Console / TTY)"
if systemctl is-active --quiet sddm 2>/dev/null; then
    DETECTED_DM="SDDM (Active)"
elif systemctl is-active --quiet gdm 2>/dev/null; then
    DETECTED_DM="GDM (Active)"
elif systemctl is-active --quiet lightdm 2>/dev/null; then
    DETECTED_DM="LightDM (Active)"
elif systemctl is-enabled --quiet sddm 2>/dev/null; then
    DETECTED_DM="SDDM (Installed, Enabled)"
elif systemctl is-enabled --quiet gdm 2>/dev/null; then
    DETECTED_DM="GDM (Installed, Enabled)"
fi
printf "  ${C_CYAN}-> Display Manager:${C_RESET} %s\n" "$DETECTED_DM"

# Detect GPU Hardware
GPU_TYPE="Generic / Integrated"
GPU_INFO=""
if command -v lspci >/dev/null 2>&1; then
    GPU_INFO="$(lspci -k 2>/dev/null | grep -EA2 -i "(VGA|3D|Display)" || true)"
elif [[ -d /sys/class/drm ]]; then
    GPU_INFO="$(cat /sys/class/drm/card*/device/vendor 2>/dev/null || true)"
fi

IS_NVIDIA=0
IS_AMD=0
IS_INTEL=0

DETECTED_GPUS=()
if grep -qi "nvidia" <<< "$GPU_INFO"; then
    DETECTED_GPUS+=("NVIDIA Dedicated GPU")
    IS_NVIDIA=1
fi
if grep -qi -E "(amd|radeon|advanced micro)" <<< "$GPU_INFO"; then
    DETECTED_GPUS+=("AMD Radeon")
    IS_AMD=1
fi
if grep -qi "intel" <<< "$GPU_INFO"; then
    DETECTED_GPUS+=("Intel Graphics")
    IS_INTEL=1
fi
GPU_TYPE="${DETECTED_GPUS[*]:-Generic / Integrated}"
printf "  ${C_CYAN}-> Graphics Card:${C_RESET}   %s\n" "$GPU_TYPE"

# Detect Virtualization
if command -v systemd-detect-virt >/dev/null 2>&1; then
    VIRT_TYPE="$(systemd-detect-virt 2>/dev/null || echo "none")"
    if [[ "$VIRT_TYPE" != "none" ]]; then
        printf "  ${C_CYAN}-> Virtualization:${C_RESET}  %s (VM detected, 3D acceleration required)\n" "$VIRT_TYPE"
    fi
fi

# Detect Current Shell
printf "  ${C_CYAN}-> User Shell:${C_RESET}      %s (%s)\n" "${SHELL}" "$USER"

# ------------------------------------------------------------------------------
# 6. Interactive Mode Selection
# ------------------------------------------------------------------------------
if [[ -z "$TARGET_MODE" ]]; then
    printf "\n${C_BOLD}%s${C_RESET}\n" "Select Installation Profile:"
    
    if [[ "$DETECTED_DE" == *"None"* ]]; then
        printf "  ${C_GREEN}[1] Fresh Arch Linux Install${C_RESET} ${C_BOLD}(Recommended for your system)${C_RESET}\n"
        printf "      Full setup: Core packages, AUR helper, GPU drivers, SDDM, audio, & configs.\n"
        printf "  ${C_YELLOW}[2] Coexist / Switch DE${C_RESET}\n"
        printf "      Install Hyprland alongside existing setups without replacing current DM.\n"
        printf "  ${C_CYAN}[3] Repair & Reconfigure${C_RESET}\n"
        printf "      Fix broken configs, permissions, themes, and hyprpm plugins.\n"
        printf "  ${C_MAGENTA}[4] Custom / Advanced Install${C_RESET}\n"
        printf "      Step-by-step interactive selection for each component.\n"
        DEFAULT_CHOICE="1"
    else
        printf "  ${C_GREEN}[1] Full Clean Install${C_RESET}\n"
        printf "      Complete Hyprland setup including SDDM Astronaut login manager.\n"
        printf "  ${C_YELLOW}[2] Coexist / Switch DE${C_RESET} ${C_BOLD}(Recommended: %s detected)${C_RESET}\n" "$DETECTED_DE"
        printf "      Safely install Hyprland alongside %s (keeps your current login manager).\n" "$DETECTED_DE"
        printf "  ${C_CYAN}[3] Repair & Reconfigure${C_RESET}\n"
        printf "      Refresh dotfiles, theme colors, and plugins without re-downloading packages.\n"
        printf "  ${C_MAGENTA}[4] Custom / Advanced Install${C_RESET}\n"
        printf "      Step-by-step interactive selection for each component.\n"
        DEFAULT_CHOICE="2"
    fi

    CHOICE="$(prompt_input "Enter selection [1-4] (default: ${DEFAULT_CHOICE}): " "$DEFAULT_CHOICE")"
    case "$CHOICE" in
        1) TARGET_MODE="fresh" ;;
        2) TARGET_MODE="switch" ;;
        3) TARGET_MODE="repair" ;;
        4) TARGET_MODE="custom" ;;
        *) TARGET_MODE="fresh" ;;
    esac
fi

step "Active Installation Profile: ${TARGET_MODE^^}"

# Configuration flags based on mode
INSTALL_PACKAGES=1
CONFIGURE_GPU=1
SETUP_SDDM=1
SETUP_SERVICES=1
DEPLOY_CONFIGS=1
SETUP_PLUGINS=1
SETUP_SHELL=1

case "$TARGET_MODE" in
    fresh)
        INSTALL_PACKAGES=1
        CONFIGURE_GPU=1
        SETUP_SDDM=1
        SETUP_SERVICES=1
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=1
        SETUP_SHELL=1
        ;;
    switch)
        INSTALL_PACKAGES=1
        CONFIGURE_GPU=1
        SETUP_SDDM=0  # Keep existing DM by default
        SETUP_SERVICES=1
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=1
        SETUP_SHELL=0  # Don't force shell switch
        ;;
    repair)
        INSTALL_PACKAGES=0
        CONFIGURE_GPU=1
        SETUP_SDDM=0
        SETUP_SERVICES=1
        DEPLOY_CONFIGS=1
        SETUP_PLUGINS=1
        SETUP_SHELL=0
        ;;
    custom)
        prompt_confirm "Install system & AUR packages?" "Y" && INSTALL_PACKAGES=1 || INSTALL_PACKAGES=0
        prompt_confirm "Configure GPU drivers & Wayland flags?" "Y" && CONFIGURE_GPU=1 || CONFIGURE_GPU=0
        prompt_confirm "Install & enable SDDM Astronaut Login Manager?" "Y" && SETUP_SDDM=1 || SETUP_SDDM=0
        prompt_confirm "Deploy dotfiles to ~/.config?" "Y" && DEPLOY_CONFIGS=1 || DEPLOY_CONFIGS=0
        prompt_confirm "Install Hyprland & VS Code plugins?" "Y" && SETUP_PLUGINS=1 || SETUP_PLUGINS=0
        prompt_confirm "Configure default user shell (Fish / Zsh)?" "Y" && SETUP_SHELL=1 || SETUP_SHELL=0
        ;;
esac

# ------------------------------------------------------------------------------
# 7. AUR Helper Setup (yay / paru)
# ------------------------------------------------------------------------------
AUR_HELPER=""

if command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif [[ "$INSTALL_PACKAGES" -eq 1 ]]; then
    step "Bootstrapping AUR Helper ('yay')"
    info "Installing base-devel and git..."
    sudo pacman -S --needed --noconfirm base-devel git
    
    YAY_BUILD_DIR="$(mktemp -d -t yay-build-XXXXXX)"
    info "Cloning yay AUR repository to ${YAY_BUILD_DIR}..."
    git clone https://aur.archlinux.org/yay.git "$YAY_BUILD_DIR"
    
    (
        cd "$YAY_BUILD_DIR"
        makepkg -si --noconfirm
    )
    
    rm -rf "$YAY_BUILD_DIR"
    AUR_HELPER="yay"
    success "'yay' successfully installed."
fi

if [[ -n "$AUR_HELPER" ]]; then
    info "Active AUR helper: ${AUR_HELPER}"
fi

# ------------------------------------------------------------------------------
# 8. Hardware & GPU Specific Packages
# ------------------------------------------------------------------------------
if [[ "$CONFIGURE_GPU" -eq 1 && "$INSTALL_PACKAGES" -eq 1 ]]; then
    step "Configuring Graphics Hardware Support"

    if [[ "$IS_NVIDIA" -eq 1 ]]; then
        info "NVIDIA GPU detected. Checking drivers..."
        if ! pacman -Qs "nvidia" >/dev/null 2>&1; then
            if prompt_confirm "Install NVIDIA proprietary drivers (DKMS) & Wayland VA-API patches?" "Y"; then
                sudo pacman -S --needed --noconfirm linux-headers nvidia-dkms nvidia-utils libva-nvidia-driver
                success "NVIDIA drivers installed."
            fi
        else
            info "NVIDIA driver already present on system."
        fi
    fi
    if [[ "$IS_AMD" -eq 1 ]]; then
        info "AMD Radeon detected. Ensuring Mesa & Vulkan packages are installed..."
        sudo pacman -S --needed --noconfirm mesa vulkan-radeon libva-mesa-driver
        success "AMD graphics packages verified."
    fi
    if [[ "$IS_INTEL" -eq 1 ]]; then
        info "Intel Graphics detected. Ensuring Mesa & Intel media drivers..."
        sudo pacman -S --needed --noconfirm mesa vulkan-intel intel-media-driver
        success "Intel graphics packages verified."
    fi
fi

# ------------------------------------------------------------------------------
# 9. Batch Package Installation (Official & AUR)
# ------------------------------------------------------------------------------
if [[ "$INSTALL_PACKAGES" -eq 1 ]]; then
    step "Installing Official Repository Packages (pacman)"
    PACMAN_PKG_FILE="${SCRIPT_DIR}/packages-pacman.txt"
    
    if [[ -f "$PACMAN_PKG_FILE" ]]; then
        mapfile -t PACMAN_PACKAGES < <(grep -vE '^\s*(#|$)' "$PACMAN_PKG_FILE")
        if [[ "${#PACMAN_PACKAGES[@]}" -gt 0 ]]; then
            info "Synchronizing ${#PACMAN_PACKAGES[@]} official packages..."
            sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"
            success "Official repository packages successfully installed."
        fi
    fi

    step "Installing AUR Packages (${AUR_HELPER:-yay})"
    AUR_PKG_FILE="${SCRIPT_DIR}/packages-aur.txt"
    
    if [[ -f "$AUR_PKG_FILE" && -n "$AUR_HELPER" ]]; then
        mapfile -t AUR_PACKAGES < <(grep -vE '^\s*(#|$)' "$AUR_PKG_FILE")
        if [[ "${#AUR_PACKAGES[@]}" -gt 0 ]]; then
            if ! "$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"; then
                warn "Batch AUR installation returned an error. Retrying packages individually..."
                for pkg in "${AUR_PACKAGES[@]}"; do
                    "$AUR_HELPER" -S --needed --noconfirm "$pkg" || warn "Package '$pkg' could not be installed."
                done
            fi
            success "AUR package installation completed."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 10. Display Manager (SDDM Astronaut Theme) Setup
# ------------------------------------------------------------------------------
if [[ "$SETUP_SDDM" -eq 1 ]]; then
    step "Configuring Display Manager (SDDM)"
    
    # Ensure SDDM package is installed
    if ! command -v sddm >/dev/null 2>&1; then
        info "Installing sddm package..."
        sudo pacman -S --needed --noconfirm sddm
    fi

    # Disable any other active DM to avoid systemd conflicts
    for dm in gdm lightdm lxdm ly; do
        if systemctl is-enabled "$dm.service" >/dev/null 2>&1; then
            warn "Disabling conflicting display manager: $dm.service"
            sudo systemctl disable "$dm.service" >/dev/null 2>&1 || true
        fi
    done

    # Enable SDDM
    sudo systemctl enable sddm.service 2>/dev/null || true
    success "SDDM service enabled."

    # Configure SDDM Theme
    SDDM_THEME_DIR="/usr/share/sddm/themes/sddm-astronaut-theme"
    if [[ -d "$SDDM_THEME_DIR" ]]; then
        info "Activating sddm-astronaut-theme..."
        sudo mkdir -p /etc/sddm.conf.d
        cat << 'EOF' | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
[Theme]
Current=sddm-astronaut-theme

[General]
InputMethod=qtvirtualkeyboard
EOF
        success "SDDM theme configured with Astronaut theme."
    fi
elif [[ "$TARGET_MODE" == "switch" ]]; then
    info "Keeping current login manager (${DETECTED_DM})."
    info "Hyprland session will be selectable at your login screen."
fi

# Verify Wayland session file exists for display manager
if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    sudo mkdir -p /usr/share/wayland-sessions
    cat << 'EOF' | sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
fi

# ------------------------------------------------------------------------------
# 11. Configuration Backup Mechanism
# ------------------------------------------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$HOME/.config/dots_backup_${TIMESTAMP}"
BACKUP_CREATED=0

backup_item() {
    local target="$1"
    local rel_path="$2"
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$BACKUP_CREATED" -eq 0 ]]; then
            step "Backing Up Existing Configurations"
            info "Destination: ${BACKUP_DIR}"
            mkdir -p "$BACKUP_DIR"
            BACKUP_CREATED=1
        fi
        local dest_parent
        dest_parent="$(dirname "$BACKUP_DIR/$rel_path")"
        mkdir -p "$dest_parent"
        mv "$target" "$BACKUP_DIR/$rel_path"
    fi
}

if [[ "$DEPLOY_CONFIGS" -eq 1 ]]; then
    shopt -s dotglob
    for item in "${SCRIPT_DIR}/.config"/*; do
        name="$(basename "$item")"
        backup_item "$HOME/.config/$name" "$name"
    done
    shopt -u dotglob

    if [[ -f "${SCRIPT_DIR}/.config/.zshrc" && -e "$HOME/.zshrc" ]]; then
        backup_item "$HOME/.zshrc" ".zshrc"
    fi

    if [[ "$BACKUP_CREATED" -eq 1 ]]; then
        success "Backup safely created at: ${BACKUP_DIR}"
    fi
fi

# ------------------------------------------------------------------------------
# 12. Deploy Configuration Files & Assets
# ------------------------------------------------------------------------------
if [[ "$DEPLOY_CONFIGS" -eq 1 ]]; then
    step "Deploying Dotfiles & Wallpapers"
    mkdir -p "$HOME/.config"
    
    # Copy all configuration directories and files
    info "Deploying configs to ~/.config..."
    shopt -s dotglob
    cp -rL "${SCRIPT_DIR}/.config"/* "$HOME/.config/"
    shopt -u dotglob

    # Configure ~/.zshrc
    if [[ -f "$HOME/.config/.zshrc" ]]; then
        cp -L "$HOME/.config/.zshrc" "$HOME/.zshrc"
    fi

    # Deploy Wallpapers
    WALLPAPER_DEST="$HOME/Pictures/Wallpapers"
    info "Deploying default wallpapers to ${WALLPAPER_DEST}..."
    mkdir -p "$WALLPAPER_DEST"

    if [[ -d "${SCRIPT_DIR}/assets/wallpapers" ]]; then
        cp -r "${SCRIPT_DIR}/assets/wallpapers"/* "$WALLPAPER_DEST/"
        ln -sfn "$WALLPAPER_DEST" "$HOME/Wallpapers"
        success "Wallpapers installed."
    fi

    # NVIDIA Wayland environment tweak
    if [[ "$IS_NVIDIA" -eq 1 ]]; then
        NVIDIA_ENV_FILE="$HOME/.config/hypr/custom/env.lua"
        if [[ -f "$NVIDIA_ENV_FILE" ]]; then
            if ! grep -q "LIBVA_DRIVER_NAME" "$NVIDIA_ENV_FILE"; then
                info "Injecting NVIDIA Wayland environment variables into custom/env.lua..."
                cat << 'EOF' >> "$NVIDIA_ENV_FILE"

-- NVIDIA Dedicated GPU Wayland optimizations
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
EOF
                success "NVIDIA Wayland flags applied."
            fi
        fi
    fi
    success "Dotfiles deployed successfully."
fi

# ------------------------------------------------------------------------------
# 13. Plugin Installation & Restoration (hyprpm & VS Code)
# ------------------------------------------------------------------------------
if [[ "$SETUP_PLUGINS" -eq 1 ]]; then
    step "Installing Plugins & Extensions"

    # Hyprland Plugins (hyprpm)
    HYPRPM_TXT="${SCRIPT_DIR}/plugins-hyprpm.txt"
    if command -v hyprpm >/dev/null 2>&1 && [[ -f "$HYPRPM_TXT" ]]; then
        info "Setting up Hyprland plugins (hyprpm)..."
        hyprpm update 2>/dev/null || true
        
        while read -r repo_url plugin_name status; do
            [[ -z "$repo_url" || "$repo_url" =~ ^# ]] && continue
            info "Installing plugin: ${plugin_name} from ${repo_url}..."
            hyprpm add "$repo_url" 2>/dev/null || true
            if [[ "$status" == "enabled" ]]; then
                hyprpm enable "$plugin_name" 2>/dev/null || true
            fi
        done < "$HYPRPM_TXT"
        
        hyprpm reload 2>/dev/null || true
        success "Hyprland plugins installed and enabled."
    fi

    # Visual Studio Code Extensions
    VSCODE_TXT="${SCRIPT_DIR}/plugins-vscode.txt"
    VSCODE_CMD=""
    if command -v code >/dev/null 2>&1; then
        VSCODE_CMD="code"
    elif command -v code-oss >/dev/null 2>&1; then
        VSCODE_CMD="code-oss"
    fi

    if [[ -n "$VSCODE_CMD" && -f "$VSCODE_TXT" ]]; then
        if prompt_confirm "Install VS Code extensions from dotfiles repository?" "Y"; then
            info "Installing VS Code extensions via ${VSCODE_CMD}..."
            while read -r ext; do
                [[ -z "$ext" || "$ext" =~ ^# ]] && continue
                "$VSCODE_CMD" --install-extension "$ext" --force 2>/dev/null || true
            done < "$VSCODE_TXT"
            success "VS Code extensions installed."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 14. Shell Setup & Selection
# ------------------------------------------------------------------------------
if [[ "$SETUP_SHELL" -eq 1 ]]; then
    step "Configuring Default User Shell"
    printf "  [1] Fish (Interactive, autosuggestions, fast)\n"
    printf "  [2] Zsh  (Starship prompt + ~/.zshrc profile)\n"
    printf "  [3] Keep current shell (%s)\n" "${SHELL}"
    
    SHELL_CHOICE="$(prompt_input "Select your preferred default shell [1-3] (default: 1): " "1")"
    case "$SHELL_CHOICE" in
        1)
            if command -v fish >/dev/null 2>&1; then
                sudo chsh -s "$(which fish)" "${USER:-$(id -un)}" 2>/dev/null || chsh -s "$(which fish)"
                success "Default shell set to Fish."
            fi
            ;;
        2)
            if command -v zsh >/dev/null 2>&1; then
                sudo chsh -s "$(which zsh)" "${USER:-$(id -un)}" 2>/dev/null || chsh -s "$(which zsh)"
                success "Default shell set to Zsh."
            fi
            ;;
        3|*)
            info "Preserved current shell: ${SHELL}"
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# 15. System Services & Permissions
# ------------------------------------------------------------------------------
step "Finalizing Services, Permissions & Theming"

# Ensure script executable permissions
info "Setting executable permissions on scripts..."
find "$HOME/.config/hypr" "$HOME/.config/quickshell" "$HOME/.config/43pr" \
    -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true

# Refresh fonts & XDG
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    xdg-user-dirs-update
fi
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -fv >/dev/null 2>&1 || true
    success "Font cache refreshed."
fi

# Papirus folders style
if command -v papirus-folders >/dev/null 2>&1; then
    papirus-folders -C white >/dev/null 2>&1 || true
fi

# Enable essential system services if fresh arch
if [[ "$TARGET_MODE" == "fresh" ]]; then
    if systemctl list-unit-files | grep -q "NetworkManager.service"; then
        sudo systemctl enable --now NetworkManager.service 2>/dev/null || true
    fi
    if systemctl list-unit-files | grep -q "bluetooth.service"; then
        sudo systemctl enable --now bluetooth.service 2>/dev/null || true
    fi
fi

# Enable user audio stack
info "Enabling user audio services (PipeWire & WirePlumber)..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user enable --now pipewire.service 2>/dev/null || true
    systemctl --user enable --now pipewire-pulse.service 2>/dev/null || true
    systemctl --user enable --now wireplumber.service 2>/dev/null || true
fi

# Apply Material 3 dynamic theme
if [[ -f "$HOME/.config/43pr/bin/theme.py" ]] && command -v python3 >/dev/null 2>&1; then
    info "Compiling initial Material 3 palette..."
    python3 "$HOME/.config/43pr/bin/theme.py" apply >/dev/null 2>&1 || true
    success "Theme palette compiled."
fi

# Setup Quickshell Python virtualenv
VENV_PATH="$HOME/.local/state/quickshell/.venv"
if [[ ! -f "$VENV_PATH/bin/python" ]] && command -v uv >/dev/null 2>&1; then
    info "Setting up Quickshell Python virtualenv..."
    uv venv "$VENV_PATH" >/dev/null 2>&1 || true
    if [[ -f "$VENV_PATH/bin/python" ]]; then
        uv pip install --python "$VENV_PATH/bin/python" pillow materialyoucolor click requests psutil numpy opencv-python pywayland libsass >/dev/null 2>&1 || true
        success "Quickshell Python virtualenv prepared."
    fi
fi

# Setup qs-wallpaper-picker
if [[ ! -d "$HOME/qs-wallpaper-picker" ]]; then
    info "Installing qs-wallpaper-picker..."
    git clone --depth 1 https://github.com/magetsu002/qs-wallpaper-picker.git "$HOME/qs-wallpaper-picker" >/dev/null 2>&1 || true
fi
if [[ -d "$HOME/qs-wallpaper-picker" ]]; then
    chmod +x "$HOME/qs-wallpaper-picker"/scripts/*.sh 2>/dev/null || true
    mkdir -p "$HOME/.cache/wallpaper_picker"
    if [[ ! -f "$HOME/.cache/wallpaper_picker/last_wallpaper" ]]; then
        echo "image|$WALLPAPER_DEST/hill-house.png" > "$HOME/.cache/wallpaper_picker/last_wallpaper"
    fi
    success "qs-wallpaper-picker configured."
fi

# Initialize wallpaper daemon
if command -v awww >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -f "$WALLPAPER_DEST/hill-house.png" ]]; then
    info "Setting default wallpaper..."
    awww-daemon >/dev/null 2>&1 &
    sleep 0.5
    awww img "$WALLPAPER_DEST/hill-house.png" >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 16. Installation Summary & Launch Instructions
# ------------------------------------------------------------------------------
printf "\n"
printf "${C_GREEN}%s${C_RESET}\n" "=========================================================="
printf "${C_BOLD}${C_GREEN}%s${C_RESET}\n" "        HYPR-DOTFILES INSTALLATION COMPLETED              "
printf "${C_GREEN}%s${C_RESET}\n" "=========================================================="
printf "\n"

printf "  -> Configs:     %s\n" "$HOME/.config"
printf "  -> Wallpapers:  %s\n" "$WALLPAPER_DEST"
if [[ "$BACKUP_CREATED" -eq 1 ]]; then
    printf "  -> Backup:      %s\n" "$BACKUP_DIR"
fi

printf "\n${C_BOLD}%s${C_RESET}\n" "How to start Hyprland:"
if [[ "$SETUP_SDDM" -eq 1 ]]; then
    printf "  [+] SDDM login manager is enabled. Simply reboot your system:\n"
    printf "      ${C_CYAN}sudo reboot${C_RESET}\n"
elif [[ "$TARGET_MODE" == "switch" ]]; then
    printf "  [+] Log out of your current desktop session, select ${C_BOLD}'Hyprland'${C_RESET} in your login screen.\n"
else
    printf "  [+] Launch directly from your current TTY console by typing:\n"
    printf "      ${C_CYAN}Hyprland${C_RESET}\n"
fi
printf "\n"
