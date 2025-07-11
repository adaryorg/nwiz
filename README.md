# Nocturne TUI

[![Build Status](https://github.com/adaryorg/nocturne/actions/workflows/build.yml/badge.svg)](https://github.com/adaryorg/nocturne/actions/workflows/build.yml)
[![Release](https://github.com/adaryorg/nocturne/actions/workflows/release.yml/badge.svg)](https://github.com/adaryorg/nocturne/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/adaryorg/nocturne)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/adaryorg/nocturne)](https://github.com/adaryorg/nocturne/releases/latest)

A powerful Terminal User Interface (TUI) application for managing the Nocturne desktop environment. Nocturne TUI provides a menu-driven interface for installation, configuration, and maintenance of all Nocturne ecosystem components.

```
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
```

## 🚀 Features

- **📋 Menu-Driven Interface**: Intuitive navigation through Nocturne components
- **⚡ Real-Time Command Execution**: Live output streaming with responsive UI  
- **🔐 Secure Sudo Management**: Background authentication with automatic renewal
- **🎨 Customizable Themes**: TOML-based theme configuration
- **📦 Installation Management**: Track and configure component installations
- **🔧 Development Mode**: `--no-sudo` flag for testing without privileges
- **📊 Version Tracking**: Build-time version info from git commits and tags

## 📦 Installation

### Download Pre-built Binary

```bash
# Download the latest release
wget https://github.com/adaryorg/nocturne/releases/latest/download/nocturne

# Make executable and install
chmod +x nocturne
sudo mv nocturne /usr/local/bin/
```

### Build from Source

#### Prerequisites
- **Zig 0.14.1+**: [Install Zig](https://ziglang.org/download/)
- **Git**: For version information during build
- **Linux**: Currently Linux-only (Ubuntu, Arch, etc.)

#### Build Steps
```bash
# Clone the repository
git clone https://github.com/adaryorg/nocturne.git
cd nocturne

# Build the project
zig build

# Install (optional)
sudo cp zig-out/bin/nocturne /usr/local/bin/
```

## 🖥️ Usage

### Basic Usage

```bash
# Run with sudo authentication (default)
nocturne

# Run without sudo (for testing/development)
nocturne --no-sudo

# Show version information
nocturne --version

# Show help
nocturne --help
```

### Command Line Options

| Option | Short | Description |
|--------|-------|-------------|
| `--version` | `-v` | Show version, commit hash, and build time |
| `--help` | `-h` | Display usage information |
| `--no-sudo` | `-n` | Skip sudo authentication (testing mode) |

### Navigation

| Key | Action |
|-----|--------|
| **↑/↓** | Navigate menu items |
| **Enter** | Execute command or enter submenu |
| **Escape** | Go back or exit |
| **←/→** | Navigate submenus intuitively |
| **Page Up/Down** | Scroll command output |
| **Ctrl+C** | Kill running command or exit |
| **q** | Quick exit |

## ⚙️ Configuration

### Directory Structure

```
~/.config/nocturne/
├── menu.toml      # Menu configuration (required)
├── theme.toml     # Theme customization (optional)
└── install.toml   # Installation selections (auto-generated)
```

### Menu Configuration (`menu.toml`)

```toml
[menu]
title = "Nocturne Main Menu"
description = "Nocturne desktop environment management"

# Hierarchical menu structure using dot notation
[menu.install]
type = "submenu"
name = "Installation"
description = "Install Nocturne components"

[menu.install.compositor]
type = "action"
name = "Install Compositor"
description = "Install the Nocturne window compositor"
command = "./scripts/install_compositor.sh"

[menu.configuration]
type = "submenu" 
name = "Configuration"
description = "Configure Nocturne settings"

[menu.configuration.themes]
type = "action"
name = "Configure Themes"
description = "Set up desktop themes"
command = "./scripts/configure_themes.sh"
```

### Theme Configuration (`theme.toml`)

```toml
[colors]
primary = "#6366f1"
secondary = "#8b5cf6"
background = "#0f172a"
text = "#f1f5f9"
accent = "#06b6d4"

[ascii_art]
enabled = true
max_height = 8
```

## 🛠️ Development

### Project Structure

```
nocturne/
├── src/
│   ├── main.zig          # Main application and event loop
│   ├── menu.zig          # Menu system and navigation
│   ├── config.zig        # TOML configuration parser
│   ├── executor.zig      # Async command execution
│   ├── sudo.zig          # Sudo authentication management
│   ├── theme.zig         # Theme configuration
│   └── install.zig       # Installation tracking
├── .github/workflows/    # CI/CD workflows
├── build.zig            # Build configuration
├── build.zig.zon        # Dependencies
└── WORKFLOW.md          # Git workflow documentation
```

### Building

```bash
# Debug build
zig build

# Release build  
zig build -Doptimize=ReleaseFast

# Run directly
zig build run

# Run with arguments
zig build run -- --no-sudo
```

### Testing

```bash
# Test basic functionality
./zig-out/bin/nocturne --version
./zig-out/bin/nocturne --help
./zig-out/bin/nocturne --no-sudo  # Quick exit test
```

## 🔄 Git Workflow

This project follows a **dev → main → release** branching strategy:

- **`dev`**: Active development and feature work
- **`main`**: Stable, tested code ready for release  
- **`release`**: Production releases with official tags

### Contributing

1. **Fork the repository**
2. **Create feature branch** from `dev`:
   ```bash
   git checkout dev
   git checkout -b feature/my-feature
   ```
3. **Make changes and commit**
4. **Create pull request** to `dev` branch
5. **Code review and merge**

See [WORKFLOW.md](WORKFLOW.md) for complete development guidelines.

## 🏗️ Architecture

### Key Components

- **Async Command Execution**: Non-blocking I/O with real-time output streaming
- **Background Sudo Management**: Automatic authentication renewal every 30 seconds
- **Hierarchical Menu System**: TOML-based configuration with dot notation
- **Memory-Safe Design**: Careful allocator management prevents leaks
- **Terminal Compatibility**: Comprehensive terminal state restoration

### Performance Features

- **25ms refresh rate** for responsive real-time output
- **50ms shutdown responsiveness** for quick exit
- **1024-byte I/O chunks** for optimal performance
- **Non-blocking UI** during command execution

## 🐛 Troubleshooting

### Common Issues

**Terminal Access Error (ENXIO)**:
```bash
Error: Unable to access /dev/tty (errno: 6 - ENXIO)
```
**Solutions**:
- Run in a fresh terminal window
- Restart terminal session after sudo usage
- Avoid running in IDE consoles
- Use native terminals (xterm, gnome-terminal)

**Build Errors**:
- Ensure Zig 0.14.1+ is installed
- Check git is available for version info
- Verify all dependencies in `build.zig.zon`

**Memory Issues**:
- The application was extensively debugged for memory leaks
- Report any new memory issues with reproduction steps

## 📊 Project Status

- ✅ **Core TUI Framework**: Complete with vaxis integration
- ✅ **Menu System**: Hierarchical TOML-based configuration  
- ✅ **Command Execution**: Async with real-time output
- ✅ **Sudo Management**: Background authentication renewal
- ✅ **CI/CD Pipeline**: Automated builds and releases
- ✅ **Command Line Interface**: Version, help, no-sudo options
- 🚧 **Configuration Bootstrap**: In development
- 🚧 **Installation Scripts**: Component-specific installers
- 🚧 **Theme System**: Advanced customization options

## 🗺️ Roadmap

See [ROADMAP.md](ROADMAP.md) for detailed development plans:

1. **Bootstrap System**: OS detection and minimal software installation
2. **OS-Specific Scripts**: Distribution-aware installation logic
3. **Update Mechanism**: Automated Nocturne component updates
4. **Advanced Menus**: Complete customization parameter interface
5. **Plugin System**: Community extensions and custom commands

## 🤝 Contributing

We welcome contributions! Please see our [contributing guidelines](WORKFLOW.md) and:

- 🐛 **Report bugs** via GitHub Issues
- 💡 **Suggest features** via GitHub Discussions  
- 🔧 **Submit pull requests** following our workflow
- 📚 **Improve documentation** and examples
- 🧪 **Add tests** for new functionality

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

## 🙏 Acknowledgments

- **[libvaxis](https://github.com/rockorager/libvaxis)**: Excellent TUI library for Zig
- **Zig Community**: Amazing language and ecosystem
- **Claude Code**: AI-assisted development and documentation

## 📞 Support

- 📧 **Email**: [Contact Adary](mailto:contact@adary.org)
- 💬 **GitHub Discussions**: [Project Discussions](https://github.com/adaryorg/nocturne/discussions)
- 🐛 **Issues**: [Bug Reports](https://github.com/adaryorg/nocturne/issues)
- 📖 **Documentation**: [Wiki](https://github.com/adaryorg/nocturne/wiki)

---

**Nocturne TUI** - Simplifying desktop environment management through intuitive terminal interfaces.