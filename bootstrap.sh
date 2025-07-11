#!/bin/bash
# SPDX-FileCopyrightText: 2025 Yuval Adar <adary@adary.org>
# SPDX-License-Identifier: MIT

set -euo pipefail

# Bootstrap script for Nocturne desktop environment
# Performs initial system setup and installation

# Setup logging to file
LOG_FILE="$HOME/.nocturne.log.$(date +%Y-%m-%d)"

# Logging functions (now log to file)
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
}

# Helper function to print error to terminal and exit
exit_with_error() {
    local error_message="$1"

    # Restore stdout/stderr to terminal if they were redirected
    exec 1>/dev/tty 2>/dev/tty

    echo
    echo "ERROR: $error_message"
    echo "Check the installation log for details: $LOG_FILE"
    echo
    exit 1
}

# Print banner to terminal only
print_banner() {
    cat <<'EOF'
 ███▄    █  ▒█████   ▄████▄  ▄▄▄█████▓ █    ██  ██▀███   ███▄    █ ▓█████ 
 ██ ▀█   █ ▒██▒  ██▒▒██▀ ▀█  ▓  ██▒ ▓▒ ██  ▓██▒▓██ ▒ ██▒ ██ ▀█   █ ▓█   ▀ 
▓██  ▀█ ██▒▒██░  ██▒▒▓█    ▄ ▒ ▓██░ ▒░▓██  ▒██░▓██ ░▄█ ▒▓██  ▀█ ██▒▒███   
▓██▒  ▐▌██▒▒██   ██░▒▓▓▄ ▄██▒░ ▓██▓ ░ ▓▓█  ░██░▒██▀▀█▄  ▓██▒  ▐▌██▒▒▓█  ▄ 
▒██░   ▓██░░ ████▓▒░▒ ▓███▀ ░  ▒██▒ ░ ▒▒█████▓ ░██▓ ▒██▒▒██░   ▓██░░▒████▒
░ ▒░   ▒ ▒ ░ ▒░▒░▒░ ░ ░▒ ▒  ░  ▒ ░░   ░▒▓▒ ▒ ▒ ░ ▒▓ ░▒▓░░ ▒░   ▒ ▒ ░░ ▒░ ░
░ ░░   ░ ▒░  ░ ▒ ▒░   ░  ▒       ░    ░░▒░ ░ ░   ░▒ ░ ▒░░ ░░   ░ ▒░ ░ ░  ░
   ░   ░ ░ ░ ░ ░ ▒  ░          ░       ░░░ ░ ░   ░░   ░    ░   ░ ░    ░   
         ░     ░ ░  ░ ░                  ░        ░              ░    ░  ░
                    ░                                                      

Nocturne Bootstrap Script - Initial System Setup
EOF
}

# Step 1: OS Detection
detect_os() {
    log_info "Detecting operating system..."

    # Check if we're on Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "This script only supports Linux systems."
        log_error "Detected OS: $(uname -s)"
        log_error "Nocturne desktop environment is currently Linux-only."
        exit_with_error "Unsupported operating system: $(uname -s). Nocturne requires Linux."
    fi

    log_success "Linux system detected"
}

# Step 2: Linux Distribution and Package Manager Detection
detect_linux_distro() {
    log_info "Detecting Linux distribution and package manager..."

    # Check if /etc/os-release exists
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found. Unable to detect distribution."
        exit_with_error "Cannot detect Linux distribution. /etc/os-release file missing."
    fi

    # Source the os-release file
    source /etc/os-release

    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${NAME:-Unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"

    log_info "Distribution: $DISTRO_NAME ($DISTRO_ID) $DISTRO_VERSION"

    # Check distribution versions and validate support
    case "$DISTRO_ID" in
    ubuntu | debian | pop | linuxmint)
        # Check for modern Ubuntu/Debian versions
        if [[ "$DISTRO_ID" == "ubuntu" ]]; then
            # Extract major and minor version (e.g., "25.04" -> major=25, minor=04)
            local version_major="${DISTRO_VERSION%%.*}"
            local version_minor="${DISTRO_VERSION#*.}"
            version_minor="${version_minor%%.*}" # Handle cases like "25.04.1"

            if [[ "$version_major" -lt 25 ]] || [[ "$version_major" -eq 25 && "$version_minor" -lt 4 ]]; then
                log_error "Ubuntu $DISTRO_VERSION is not supported. Please use Ubuntu 25.04 or newer."
                exit_with_error "Unsupported Ubuntu version: $DISTRO_VERSION. Please upgrade to Ubuntu 25.04 or newer."
            fi
        elif [[ "$DISTRO_ID" == "debian" ]]; then
            if [[ "${DISTRO_VERSION%%.*}" -lt 13 ]]; then
                log_error "Debian $DISTRO_VERSION is not supported. Please use Debian 13 (Trixie) or newer."
                exit_with_error "Unsupported Debian version: $DISTRO_VERSION. Please upgrade to Debian 13 (Trixie) or newer."
            fi
        fi
        log_success "APT-based distribution validated"
        ;;
    fedora)
        # Check for supported Fedora versions (42+)
        if [[ "${DISTRO_VERSION%%.*}" -lt 42 ]]; then
            log_error "Fedora $DISTRO_VERSION is not supported. Please use Fedora 42 or newer."
            exit_with_error "Unsupported Fedora version: $DISTRO_VERSION. Please upgrade to Fedora 42 or newer."
        fi
        log_success "DNF-based distribution validated"
        ;;
    opensuse-tumbleweed)
        log_info "openSUSE Tumbleweed detected (rolling release)"
        log_success "Zypper-based distribution validated"
        ;;
    arch | manjaro | endeavouros)
        log_info "Arch-based distribution detected (rolling release)"
        log_success "Pacman-based distribution validated"
        ;;
    # Explicitly unsupported enterprise/legacy distributions
    rhel | centos | rocky | almalinux)
        log_error "Enterprise Linux distributions are not supported by Nocturne."
        log_error "Detected: $DISTRO_NAME"
        log_error "Please use a modern desktop-oriented Linux distribution."
        exit_with_error "Enterprise Linux distribution detected: $DISTRO_NAME. Please use a modern desktop distribution."
        ;;
    opensuse-leap | sles | sled)
        log_error "openSUSE Leap and SUSE Enterprise are not supported."
        log_error "Please use openSUSE Tumbleweed for SUSE-based systems."
        exit_with_error "Unsupported SUSE distribution: $DISTRO_NAME. Please use openSUSE Tumbleweed."
        ;;
    alpine)
        log_error "Alpine Linux is not currently supported by Nocturne."
        log_error "Please use a desktop-oriented distribution with glibc."
        exit_with_error "Alpine Linux is not supported. Please use a glibc-based desktop distribution."
        ;;
    *)
        log_error "Unsupported distribution: $DISTRO_ID ($DISTRO_NAME)"
        log_error ""
        log_error "Nocturne supports these modern Linux distributions:"
        log_error "  • Ubuntu 25.04 or newer"
        log_error "  • Debian 13 (Trixie) or newer"
        log_error "  • Fedora 42 or newer"
        log_error "  • Arch Linux (and derivatives: Manjaro, EndeavourOS)"
        log_error "  • openSUSE Tumbleweed"
        log_error ""
        log_error "Enterprise and legacy distributions are not supported."
        exit_with_error "Unsupported Linux distribution: $DISTRO_NAME. See supported distributions in log file."
        ;;
    esac
}

# Step 3: Install Prerequisites
install_prerequisites() {
    log_info "Checking for required prerequisites..."

    local packages_to_install=()

    # Check for git
    if command -v git >/dev/null 2>&1; then
        log_success "Git is already installed: $(git --version)"
    else
        log_info "Git not found, will be installed"
        packages_to_install+=("git")
    fi

    # Check for wget
    if command -v wget >/dev/null 2>&1; then
        log_success "Wget is already installed: $(wget --version | head -n1)"
    else
        log_info "Wget not found, will be installed"
        packages_to_install+=("wget")
    fi

    # For Arch-based distributions, add base-devel for AUR support
    case "$DISTRO_ID" in
    arch | manjaro | endeavouros)
        # Check if base-devel is installed by checking for makepkg
        if command -v makepkg >/dev/null 2>&1; then
            log_success "Base-devel is already installed"
        else
            log_info "Base-devel not found, will be installed for AUR support"
            packages_to_install+=("base-devel")
        fi
        ;;
    esac

    # Install missing packages if any
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "Installing missing prerequisites: ${packages_to_install[*]}"

        case "$DISTRO_ID" in
        ubuntu | debian | pop | linuxmint)
            sudo apt update >>"$LOG_FILE" 2>&1 && sudo apt install -y "${packages_to_install[@]}" >>"$LOG_FILE" 2>&1
            ;;
        fedora)
            sudo dnf install -y "${packages_to_install[@]}" >>"$LOG_FILE" 2>&1
            ;;
        opensuse-tumbleweed)
            sudo zypper install -y "${packages_to_install[@]}" >>"$LOG_FILE" 2>&1
            ;;
        arch | manjaro | endeavouros)
            sudo pacman -S --noconfirm "${packages_to_install[@]}" >>"$LOG_FILE" 2>&1
            ;;
        *)
            log_error "Unknown distribution: $DISTRO_ID"
            log_error "This should not happen after distribution detection."
            exit_with_error "Internal error: Unknown distribution during package installation."
            ;;
        esac

        # Verify installations
        for package in "${packages_to_install[@]}"; do
            case "$package" in
            git)
                if command -v git >/dev/null 2>&1; then
                    log_success "Git installed successfully: $(git --version)"
                else
                    log_error "Failed to install git"
                    exit_with_error "Git installation failed. Check your package manager and network connection."
                fi
                ;;
            wget)
                if command -v wget >/dev/null 2>&1; then
                    log_success "Wget installed successfully: $(wget --version | head -n1)"
                else
                    log_error "Failed to install wget"
                    exit_with_error "Wget installation failed. Check your package manager and network connection."
                fi
                ;;
            base-devel)
                if command -v makepkg >/dev/null 2>&1; then
                    log_success "Base-devel installed successfully"
                else
                    log_error "Failed to install base-devel"
                    exit_with_error "Base-devel installation failed. Check your package manager and network connection."
                fi
                ;;
            esac
        done
    else
        log_success "All prerequisites are already installed"
    fi

    # Install yay for Arch-based distributions
    case "$DISTRO_ID" in
    arch | manjaro | endeavouros)
        install_yay
        ;;
    esac
}

# Install yay AUR helper for Arch-based distributions
install_yay() {
    log_info "Checking for yay AUR helper..."

    if command -v yay >/dev/null 2>&1; then
        log_success "Yay is already installed: $(yay --version | head -n1)"
        return 0
    fi

    log_info "Yay not found. Installing yay from AUR..."

    local yay_dir="/tmp/yay"

    # Remove existing yay directory if it exists
    if [[ -d "$yay_dir" ]]; then
        log_info "Removing existing /tmp/yay directory"
        rm -rf "$yay_dir"
    fi

    # Clone yay from AUR
    log_info "Cloning yay from AUR..."
    if git clone https://aur.archlinux.org/yay.git "$yay_dir" >>"$LOG_FILE" 2>&1; then
        log_success "Yay repository cloned to /tmp/yay"
    else
        log_error "Failed to clone yay repository"
        exit_with_error "Could not clone yay AUR helper. Check your network connection."
    fi

    # Build and install yay
    log_info "Building and installing yay..."
    if (cd "$yay_dir" && makepkg -si --noconfirm >>"$LOG_FILE" 2>&1); then
        log_success "Yay installed successfully"
    else
        log_error "Failed to build and install yay"
        log_error "Please check makepkg output for details"
        exit_with_error "Yay AUR helper installation failed. Check makepkg dependencies."
    fi

    # Clean up
    log_info "Cleaning up /tmp/yay directory"
    rm -rf "$yay_dir"

    # Verify installation
    if command -v yay >/dev/null 2>&1; then
        log_success "Yay is working correctly: $(yay --version | head -n1)"
    else
        log_error "Yay installation failed verification"
        exit_with_error "Yay installation verification failed. Binary not found after installation."
    fi
}

# Step 4: Setup Directory Structure
setup_directories() {
    log_info "Setting up directory structure..."

    # Handle ~/.local/share/nocturne
    if [[ -d "$HOME/.local/share/nocturne" ]]; then
        log_warning "~/.local/share/nocturne already exists"
        if [[ -d "$HOME/.local/share/nocturne_old" ]]; then
            log_info "Removing existing ~/.local/share/nocturne_old backup"
            rm -rf "$HOME/.local/share/nocturne_old"
        fi
        log_info "Moving ~/.local/share/nocturne to ~/.local/share/nocturne_old"
        mv "$HOME/.local/share/nocturne" "$HOME/.local/share/nocturne_old"
    fi

    # Handle ~/.config/nocturne
    if [[ -d "$HOME/.config/nocturne" ]]; then
        log_warning "~/.config/nocturne already exists"
        if [[ -d "$HOME/.config/nocturne_old" ]]; then
            log_info "Removing existing ~/.config/nocturne_old backup"
            rm -rf "$HOME/.config/nocturne_old"
        fi
        log_info "Moving ~/.config/nocturne to ~/.config/nocturne_old"
        mv "$HOME/.config/nocturne" "$HOME/.config/nocturne_old"
    fi

    # Create required directories
    if [[ ! -d "$HOME/.local/bin" ]]; then
        log_info "Creating ~/.local/bin directory"
        mkdir -p "$HOME/.local/bin"
    fi

    if [[ ! -d "$HOME/.local/share" ]]; then
        log_info "Creating ~/.local/share directory"
        mkdir -p "$HOME/.local/share"
    fi

    # Create ~/.config/nocturne directory during bootstrap
    if [[ ! -d "$HOME/.config/nocturne" ]]; then
        log_info "Creating ~/.config/nocturne directory"
        mkdir -p "$HOME/.config/nocturne"
    fi

    log_success "Directory structure prepared"
}

# Step 5: Clone Nocturne Repository
clone_repository() {
    log_info "Cloning Nocturne repository..."

    local repo_url="https://github.com/adaryorg/nocturne.git"
    local target_dir="$HOME/.local/share/nocturne"

    # Clone the repository
    if git clone "$repo_url" "$target_dir" >>"$LOG_FILE" 2>&1; then
        log_success "Repository cloned to ~/.local/share/nocturne"
    else
        log_error "Failed to clone repository from $repo_url"
        exit_with_error "Could not clone Nocturne repository. Check your network connection."
    fi
}

# Step 6: Download Nocturne Binary
download_binary() {
    log_info "Downloading latest Nocturne binary..."

    local binary_url="https://github.com/adaryorg/nocturne/releases/latest/download/nocturne"
    local target_file="$HOME/.local/bin/nocturne"

    # Download the binary using wget (installed as prerequisite)
    if wget -O "$target_file" "$binary_url" >>"$LOG_FILE" 2>&1; then
        chmod +x "$target_file"
        log_success "Nocturne binary downloaded to ~/.local/bin/nocturne"
    else
        log_error "Failed to download binary using wget"
        exit_with_error "Could not download Nocturne binary. Check your network connection."
    fi
}

# Step 7: Copy Initial Configuration Files
copy_initial_config() {
    log_info "Copying initial configuration files..."

    local source_config_dir="$HOME/.local/share/nocturne/config"
    local target_config_dir="$HOME/.config/nocturne"

    # Check if source config directory exists in the cloned repository
    if [[ ! -d "$source_config_dir" ]]; then
        log_warning "No config directory found in repository at $source_config_dir"
        log_info "Configuration files will be created on first run"
        return 0
    fi

    # List available TOML files for logging
    local toml_files=("$source_config_dir"/*.toml)
    if [[ -f "${toml_files[0]}" ]]; then
        log_info "Found config files in repository:"
        for file in "${toml_files[@]}"; do
            log_info "  - $(basename "$file")"
        done

        log_info "Copying TOML configuration files to ~/.config/nocturne"
        cp "$source_config_dir"/*.toml "$target_config_dir/" 2>>"$LOG_FILE"

        # Verify files were copied
        local copied_files=("$target_config_dir"/*.toml)
        if [[ -f "${copied_files[0]}" ]]; then
            log_success "Configuration files copied successfully:"
            for file in "${copied_files[@]}"; do
                log_success "  - $(basename "$file")"
            done
        else
            log_error "Failed to copy configuration files"
            exit_with_error "Could not copy configuration files from repository."
        fi
    else
        log_info "No TOML files found in repository config directory"
        log_info "Configuration files will be created on first run"
    fi
}

# Step 8: Verify Installation
verify_installation() {
    log_info "Verifying installation..."

    # Check if binary exists and is executable
    if [[ -x "$HOME/.local/bin/nocturne" ]]; then
        log_success "Nocturne binary is installed and executable"

        # Add ~/.local/bin to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            log_info "Adding ~/.local/bin to PATH"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"
            log_info "Please run 'source ~/.bashrc' or restart your terminal"
        fi

        # Test version output
        if "$HOME/.local/bin/nocturne" --version >/dev/null 2>&1; then
            log_success "Nocturne binary is working correctly"
        else
            log_warning "Nocturne binary exists but may not be working properly"
        fi
    else
        log_error "Nocturne binary installation failed"
        exit_with_error "Nocturne binary is not executable. Download may have failed."
    fi

    # Check repository
    if [[ -d "$HOME/.local/share/nocturne/.git" ]]; then
        log_success "Nocturne repository is properly cloned"
    else
        log_error "Nocturne repository was not cloned properly"
        exit_with_error "Nocturne repository verification failed. Clone may have been incomplete."
    fi
}

# Main execution
main() {
    print_banner
    echo "Installing prerequisites and preparing Nocturne installation..."
    echo "Detailed logs: $LOG_FILE"
    echo

    # Redirect all logging to file from this point forward
    exec 1>>"$LOG_FILE"
    exec 2>>"$LOG_FILE"

    log_info "Starting Nocturne bootstrap process..."

    detect_os
    detect_linux_distro
    install_prerequisites
    setup_directories
    clone_repository
    download_binary
    copy_initial_config
    verify_installation

    # Restore stdout for final terminal message
    exec 1>/dev/tty
    exec 2>/dev/tty

    echo
    echo "Nocturne bootstrap completed successfully!"
    echo "Full installation log: $LOG_FILE"
    echo
    echo "Attempting to start Nocturne TUI"
    nocturne
}

# Run main function
main "$@"
