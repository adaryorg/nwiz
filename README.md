# nwizard

[![Build Status](https://github.com/adaryorg/nwizard/actions/workflows/build.yml/badge.svg)](https://github.com/adaryorg/nocturne/actions/workflows/build.yml)
[![Release](https://github.com/adaryorg/nwizard/actions/workflows/release.yml/badge.svg)](https://github.com/adaryorg/nocturne/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/adaryorg/nwizard)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/adaryorg/nwizard)](https://github.com/adaryorg/nwizard/releases/latest)

A terminal-based installation wizard for the Nocturne desktop environment ecosystem. Provides menu-driven configuration and component management through a clean TUI interface.

## Features

- Menu-driven navigation with TOML configuration
- Real-time command execution with live output
- Installation state tracking and persistence
- Theme customization support
- Configuration validation and linting
- Command-line utilities for scripting integration

## Installation

### From Release

```bash
wget https://github.com/adaryorg/nwizard/releases/latest/download/nwizard
chmod +x nwizard
sudo mv nwizard /usr/local/bin/
```

### From Source

Requires Zig 0.14.1+:

```bash
git clone https://github.com/adaryorg/nwizard.git
cd nwizard
zig build
sudo cp zig-out/bin/nwizard /usr/local/bin/
```

## Usage

### Basic Operation

```bash
# Start the TUI interface
nwizard

# Use custom configuration
nwizard --config /path/to/menu.toml

# Test mode without sudo
nwizard --no-sudo
```

### Command Line Tools

```bash
# Validate menu configuration
nwizard --lint menu.toml

# Export configuration as environment variables
eval $(nwizard --read-configuration-options install.toml)

# Show available themes
nwizard --show-themes
```

### Navigation

| Key | Action |
|-----|--------|
| Up/Down | Navigate items |
| Enter | Select/execute |
| Escape | Go back |
| Left/Right | Navigate submenus |
| q | Exit |
| Ctrl+C | Kill command |

## Configuration

Configuration files are stored in `~/.config/nwizard/`:

- `menu.toml` - Menu structure and commands (required)
- `theme.toml` - Visual customization (optional)  
- `install.toml` - Installation state (auto-generated)

### Menu Configuration

```toml
[menu]
title = "Main Menu"
description = "System management"

[menu.install]
type = "submenu"
name = "Installation"

[menu.install.packages]
type = "multiple_selection"
name = "Select Packages"
options = ["git", "vim", "tmux"]
install_key = "PACKAGES"

[menu.install.browser]
type = "selector"
name = "Default Browser"
options = ["firefox", "chromium"]
variable = "BROWSER"
```

## Development

### Project Structure

- `src/main.zig` - Main application and event loop
- `src/cli.zig` - Command line argument handling
- `src/menu.zig` - Menu system and navigation
- `src/config.zig` - TOML configuration parsing
- `src/executor.zig` - Async command execution
- `src/theme.zig` - Theme management
- `src/install.zig` - Installation state tracking

### Building

```bash
zig build          # Debug build
zig build -Drelease # Release build
```

### Contributing

1. Create feature branch: `git checkout -b feature/name`
2. Make changes and test
3. Submit pull request to `main`

See [WORKFLOW.md](WORKFLOW.md) for detailed development guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.