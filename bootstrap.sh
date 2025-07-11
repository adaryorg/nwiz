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

# Print banner to terminal only
print_banner() {
    cat << 'EOF'
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
        exit 1
    fi
    
    log_success "Linux system detected"
}

# Step 2: Linux Distribution and Package Manager Detection
detect_linux_distro() {
    log_info "Detecting Linux distribution and package manager..."
    
    # Check if /etc/os-release exists
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found. Unable to detect distribution."
        exit 1
    fi
    
    # Source the os-release file
    source /etc/os-release
    
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${NAME:-Unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    
    log_info "Distribution: $DISTRO_NAME ($DISTRO_ID) $DISTRO_VERSION"
    
    # Detect package manager based on distribution
    case "$DISTRO_ID" in
        ubuntu|debian|pop|linuxmint)
            PACKAGE_MANAGER="apt"
            INSTALL_CMD="apt update && apt install -y"
            # Check for modern Ubuntu/Debian versions
            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                # Extract major and minor version (e.g., "25.04" -> major=25, minor=04)
                local version_major="${DISTRO_VERSION%%.*}"
                local version_minor="${DISTRO_VERSION#*.}"
                version_minor="${version_minor%%.*}" # Handle cases like "25.04.1"
                
                if [[ "$version_major" -lt 25 ]] || [[ "$version_major" -eq 25 && "$version_minor" -lt 4 ]]; then
                    log_error "Ubuntu $DISTRO_VERSION is not supported. Please use Ubuntu 25.04 or newer."
                    exit 1
                fi
            elif [[ "$DISTRO_ID" == "debian" ]]; then
                if [[ "${DISTRO_VERSION%%.*}" -lt 13 ]]; then
                    log_error "Debian $DISTRO_VERSION is not supported. Please use Debian 13 (Trixie) or newer."
                    exit 1
                fi
            fi
            ;;
        fedora)
            PACKAGE_MANAGER="dnf"
            INSTALL_CMD="dnf install -y"
            # Check for supported Fedora versions (42+)
            if [[ "${DISTRO_VERSION%%.*}" -lt 42 ]]; then
                log_error "Fedora $DISTRO_VERSION is not supported. Please use Fedora 42 or newer."
                exit 1
            fi
            ;;
        opensuse-tumbleweed)
            PACKAGE_MANAGER="zypper"
            INSTALL_CMD="zypper install -y"
            log_info "openSUSE Tumbleweed detected (rolling release)"
            ;;
        arch|manjaro|endeavouros)
            PACKAGE_MANAGER="pacman"
            INSTALL_CMD="pacman -S --noconfirm"
            log_info "Arch-based distribution detected (rolling release)"
            ;;
        # Explicitly unsupported enterprise/legacy distributions
        rhel|centos|rocky|almalinux)
            log_error "Enterprise Linux distributions are not supported by Nocturne."
            log_error "Detected: $DISTRO_NAME"
            log_error "Please use a modern desktop-oriented Linux distribution."
            exit 1
            ;;
        opensuse-leap|sles|sled)
            log_error "openSUSE Leap and SUSE Enterprise are not supported."
            log_error "Please use openSUSE Tumbleweed for SUSE-based systems."
            exit 1
            ;;
        alpine)
            log_error "Alpine Linux is not currently supported by Nocturne."
            log_error "Please use a desktop-oriented distribution with glibc."
            exit 1
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
            exit 1
            ;;
    esac
    
    log_success "Package manager: $PACKAGE_MANAGER"
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
    if [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
        # Check if base-devel is installed by checking for makepkg
        if command -v makepkg >/dev/null 2>&1; then
            log_success "Base-devel is already installed"
        else
            log_info "Base-devel not found, will be installed for AUR support"
            packages_to_install+=("base-devel")
        fi
    fi
    
    # Install missing packages if any
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log_info "Installing missing prerequisites: ${packages_to_install[*]}"
        
        case "$PACKAGE_MANAGER" in
            apt)
                sudo apt update >> "$LOG_FILE" 2>&1 && sudo apt install -y "${packages_to_install[@]}" >> "$LOG_FILE" 2>&1
                ;;
            dnf)
                sudo dnf install -y "${packages_to_install[@]}" >> "$LOG_FILE" 2>&1
                ;;
            zypper)
                sudo zypper install -y "${packages_to_install[@]}" >> "$LOG_FILE" 2>&1
                ;;
            pacman)
                sudo pacman -S --noconfirm "${packages_to_install[@]}" >> "$LOG_FILE" 2>&1
                ;;
            *)
                log_error "Unknown package manager: $PACKAGE_MANAGER"
                log_error "This should not happen after distribution detection."
                exit 1
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
                        exit 1
                    fi
                    ;;
                wget)
                    if command -v wget >/dev/null 2>&1; then
                        log_success "Wget installed successfully: $(wget --version | head -n1)"
                    else
                        log_error "Failed to install wget"
                        exit 1
                    fi
                    ;;
                base-devel)
                    if command -v makepkg >/dev/null 2>&1; then
                        log_success "Base-devel installed successfully"
                    else
                        log_error "Failed to install base-devel"
                        exit 1
                    fi
                    ;;
            esac
        done
    else
        log_success "All prerequisites are already installed"
    fi
    
    # Install yay for Arch-based distributions
    if [[ "$PACKAGE_MANAGER" == "pacman" ]]; then
        install_yay
    fi
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
    if git clone https://aur.archlinux.org/yay.git "$yay_dir" >> "$LOG_FILE" 2>&1; then
        log_success "Yay repository cloned to /tmp/yay"
    else
        log_error "Failed to clone yay repository"
        exit 1
    fi
    
    # Build and install yay
    log_info "Building and installing yay..."
    if (cd "$yay_dir" && makepkg -si --noconfirm >> "$LOG_FILE" 2>&1); then
        log_success "Yay installed successfully"
    else
        log_error "Failed to build and install yay"
        log_error "Please check makepkg output for details"
        exit 1
    fi
    
    # Clean up
    log_info "Cleaning up /tmp/yay directory"
    rm -rf "$yay_dir"
    
    # Verify installation
    if command -v yay >/dev/null 2>&1; then
        log_success "Yay is working correctly: $(yay --version | head -n1)"
    else
        log_error "Yay installation failed verification"
        exit 1
    fi
}

# Step 4: Setup Directory Structure
setup_directories() {
    log_info "Setting up directory structure..."
    
    # Handle ~/.local/nocturne
    if [[ -d "$HOME/.local/nocturne" ]]; then
        log_warning "~/.local/nocturne already exists"
        if [[ -d "$HOME/.local/nocturne_old" ]]; then
            log_info "Removing existing ~/.local/nocturne_old backup"
            rm -rf "$HOME/.local/nocturne_old"
        fi
        log_info "Moving ~/.local/nocturne to ~/.local/nocturne_old"
        mv "$HOME/.local/nocturne" "$HOME/.local/nocturne_old"
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
    local target_dir="$HOME/.local/nocturne"
    
    # Clone the repository
    if git clone "$repo_url" "$target_dir" >> "$LOG_FILE" 2>&1; then
        log_success "Repository cloned to ~/.local/nocturne"
    else
        log_error "Failed to clone repository from $repo_url"
        exit 1
    fi
}

# Step 6: Download Nocturne Binary
download_binary() {
    log_info "Downloading latest Nocturne binary..."
    
    local binary_url="https://github.com/adaryorg/nocturne/releases/latest/download/nocturne"
    local target_file="$HOME/.local/bin/nocturne"
    
    # Download the binary using wget (installed as prerequisite)
    if wget -O "$target_file" "$binary_url" >> "$LOG_FILE" 2>&1; then
        chmod +x "$target_file"
        log_success "Nocturne binary downloaded to ~/.local/bin/nocturne"
    else
        log_error "Failed to download binary using wget"
        exit 1
    fi
}

# Step 7: Copy Initial Configuration Files
copy_initial_config() {
    log_info "Copying initial configuration files..."
    
    local source_config_dir="$HOME/.local/nocturne/config"
    local target_config_dir="$HOME/.config/nocturne"
    
    # Check if source config directory exists in the cloned repository
    if [[ ! -d "$source_config_dir" ]]; then
        log_warning "No config directory found in repository at $source_config_dir"
        log_info "Configuration files will be created on first run"
        return 0
    fi
    
    # Copy all TOML files from the repository config directory
    if find "$source_config_dir" -name "*.toml" -type f | read; then
        log_info "Copying TOML configuration files to ~/.config/nocturne"
        cp "$source_config_dir"/*.toml "$target_config_dir/"
        log_success "Configuration files copied successfully"
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
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
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
        exit 1
    fi
    
    # Check repository
    if [[ -d "$HOME/.local/nocturne/.git" ]]; then
        log_success "Nocturne repository is properly cloned"
    else
        log_error "Nocturne repository was not cloned properly"
        exit 1
    fi
}

# Step 9: Print Next Steps
print_next_steps() {
    echo
    log_success "Nocturne bootstrap completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Add ~/.local/bin to your PATH (if not done automatically):"
    echo "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo "   source ~/.bashrc"
    echo
    echo "2. Run Nocturne TUI:"
    echo "   nocturne"
    echo
    echo "3. Or run with full path:"
    echo "   ~/.local/bin/nocturne"
    echo
    echo "Installation locations:"
    echo "  • Binary: ~/.local/bin/nocturne"
    echo "  • Repository: ~/.local/nocturne"
    echo "  • Configuration: ~/.config/nocturne"
    echo
    if [[ -d "$HOME/.local/nocturne_old" ]] || [[ -d "$HOME/.config/nocturne_old" ]]; then
        echo "Backups created:"
        [[ -d "$HOME/.local/nocturne_old" ]] && echo "  • Previous installation: ~/.local/nocturne_old"
        [[ -d "$HOME/.config/nocturne_old" ]] && echo "  • Previous configuration: ~/.config/nocturne_old"
        echo
    fi
}

# Main execution
main() {
    print_banner
    echo "Installing prerequisites and preparing Nocturne installation..."
    echo "Detailed logs: $LOG_FILE"
    echo
    
    # Redirect all logging to file from this point forward
    exec 1>> "$LOG_FILE"
    exec 2>> "$LOG_FILE"
    
    log_info "Starting Nocturne bootstrap process..."
    echo
    
    detect_os
    detect_linux_distro
    install_prerequisites
    setup_directories
    clone_repository
    download_binary
    copy_initial_config
    verify_installation
    
    echo
    print_next_steps
    
    # Restore stdout for final terminal message
    exec 1>/dev/tty
    exec 2>/dev/tty
    
    echo
    echo "Nocturne bootstrap completed successfully!"
    echo "Full installation log: $LOG_FILE"
    echo
    echo "Run 'nocturne' to start the Nocturne TUI"
    echo "(You may need to restart your terminal or run 'source ~/.bashrc' first)"
}

# Run main function
main "$@"