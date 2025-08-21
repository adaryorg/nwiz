# nwiz User Guide

## Introduction

nwiz is a terminal user interface application for managing system configurations, installations, and maintenance tasks through a menu-driven interface. This guide explains how to use the application, create custom menus, and integrate it with your scripts and workflows.

## Building and Installation

To build nwiz from source, you need Zig compiler version 0.13.0 or later. Run the following command in the project directory:

```bash
zig build
```

The compiled binary will be available at `./zig-out/bin/nwiz`. You can copy this binary to a location in your PATH for system-wide access.

## Basic Usage

### Starting the Application

Run the application with:

```bash
nwiz
```

By default, nwiz looks for configuration files in `~/.config/nwiz/`. You can specify a custom menu configuration:

```bash
nwiz --config /path/to/menu.toml
```

### Command Line Options

The application supports several command line options:

```bash
# General options
nwiz -h, --help                    # Show help information
nwiz -v, --version                 # Display version information
nwiz -n, --no-sudo                 # Run without sudo authentication

# Configuration
nwiz -c, --config <path>           # Use custom menu configuration
nwiz -t, --theme <name|path>       # Use theme name (built-in) or file path
nwiz --install-config-dir <path>   # Custom directory for install.toml

# Theme utilities
nwiz --list-themes                 # List available built-in theme names only
nwiz --show-theme <name>           # Preview a single specific theme
nwiz --show-themes                 # Preview ALL built-in themes at once
nwiz --write-theme <path>          # Export current theme to TOML file

# Validation and scripting
nwiz --lint <menu.toml>            # Validate menu configuration file
nwiz --config-options <install.toml>  # Export config as NWIZ_* env variables

# Batch mode execution
nwiz --batch                        # Run all actions automatically
nwiz --batch --answer-file <file>   # Use TOML answer file for values
```

### Navigation

Once the TUI starts, you can navigate using these keys:

- Arrow Up/Down: Navigate menu items
- Enter: Select item or execute command
- Escape: Go back to parent menu or exit from root
- Left Arrow: Go back to parent menu
- Right Arrow: Enter submenu or selector
- q: Quit the application
- Space: Toggle option in multiple selection mode

When viewing command output:
- Arrow Up/Down: Scroll line by line
- Page Up/Page Down: Scroll by pages
- g: Jump to top of output
- Shift+G: Jump to bottom and follow output
- s: Toggle output visibility
- c: Kill running command
- Escape: Return to menu

## Creating Menu Configurations

### Menu Structure

Menus are defined in TOML format using a hierarchical key-based structure. Every menu configuration must start with a root `[menu]` section that defines global settings for the entire menu system. All menu items must then branch from this root using dot notation, such as `[menu.network]` for a top-level item or `[menu.network.ping]` for a nested item.

The hierarchy works as follows:
- `[menu]` - Root configuration with global settings (title, description, shell)
- `[menu.item]` - First-level menu items displayed in the main menu
- `[menu.item.subitem]` - Second-level items displayed when entering the parent item
- `[menu.item.subitem.deepitem]` - Third-level items, and so on

The menu system automatically infers parent-child relationships from these key paths. If you define `[menu.tools.network.ping]`, the system automatically creates a "tools" submenu containing a "network" submenu, which contains the "ping" action.

### Basic Menu Example

Create a file called `menu.toml`:

```toml
[menu]
title = "System Management"
description = "Main system management menu"
sudo_refresh_period = 300  # Optional: sudo refresh interval in seconds (5 minutes)
ascii_art = [
    "███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗",
    "██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║",
    "███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║",
    "╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║",
    "███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║",
    "╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝"
]

[menu.network]
type = "submenu"
name = "Network Tools"
description = "Network configuration and testing"

[menu.network.ping]
type = "action"
name = "Ping Google DNS"
description = "Test internet connectivity"
command = "ping -c 4 8.8.8.8"

[menu.network.ifconfig]
type = "action"
name = "Show Network Interfaces"
description = "Display network configuration"
command = "ip addr show"

[menu.system]
type = "submenu"
name = "System Information"
description = "View system details"

[menu.system.memory]
type = "action"
name = "Memory Usage"
description = "Show memory statistics"
command = "free -h"

[menu.system.disk]
type = "action"
name = "Disk Usage"
description = "Show disk space usage"
command = "df -h"
```

### Menu Item Types

There are three main types of menu items:

**Action Items** execute commands when selected:

```toml
[menu.update]
type = "action"
name = "System Update"
description = "Update system packages"
command = "./scripts/system-update.sh"
```

**Best Practice: Use Shell Scripts Instead of Direct Commands**

While nwiz supports running any system command directly in the `command` field, **shell scripts are strongly recommended** for better maintainability and functionality:

```toml
# RECOMMENDED: Use shell scripts
[menu.system_info]
type = "action"
name = "System Information"
description = "Display system details"
command = "./scripts/system-info.sh"

# DISCOURAGED: Direct commands (though they work)
[menu.system_info_direct]
type = "action"  
name = "System Information"
description = "Display system details"
command = "echo '=== CPU ==='; top -bn1 | head -5; echo '=== Memory ==='; free -h"
```

**Benefits of using shell scripts:**
- **Variable Access**: Scripts can load configuration using `eval $(nwiz --config-options config/install.toml)` to access user selections
- **Better Error Handling**: Proper exit codes and error handling
- **Maintainability**: Easier to modify and debug complex operations
- **Reusability**: Scripts can be called from multiple menu items
- **Status Messages**: Better integration with status message system
- **Complex Logic**: Support for loops, conditionals, and advanced shell features

**Example script with configuration loading:**
```bash
#!/bin/bash
# Load user selections from install.toml
eval $(nwiz --config-options config/install.toml)

echo "[SETUP] Configuring ${NWIZ_THEME:-default} theme"
# Use the loaded variables in your script (note NWIZ_ prefix)
echo "Selected editor: ${NWIZ_EDITOR_TYPE:-vim}"
echo "Selected shell: ${NWIZ_SHELL_TYPE:-bash}"
```

Actions support optional parameters to control their behavior:

**Output Display Control (`show_output`)**:
```toml
[menu.ping_with_output]
type = "action"
name = "Network Test"
description = "Test connectivity with output visible from start"
command = "ping -c 10 8.8.8.8"
show_output = true

[menu.ping_with_spinner]  
type = "action"
name = "Quick Check"
description = "Fast command with spinner initially"
command = "uptime"
show_output = false
```

The `show_output` parameter behavior:
- **Not specified**: Default behavior - starts with spinner, user can toggle with 's' key
- **`show_output = true`**: Starts with command output visible immediately
- **`show_output = false`**: Explicitly starts with spinner (same as default)

**Disclaimer Dialog (`disclaimer`)**:
```toml
[menu.system.critical_operation]
type = "action"
name = "Critical System Operation"
description = "Perform system-wide changes"
command = "sudo systemctl restart networking"
disclaimer = "disclaimers/network-restart-warning.txt"

[menu.data.destructive_action]
type = "action"
name = "Delete Old Backups"
description = "Remove backups older than 30 days"
command = "./scripts/cleanup-backups.sh --days=30"
disclaimer = "/etc/nwiz/data-deletion-disclaimer.txt"
```

The `disclaimer` parameter behavior:
- **Not specified**: Action executes immediately when selected
- **File path specified**: Shows disclaimer dialog before execution
  - Path can be relative to current working directory or absolute
  - User can proceed (Y) or cancel (N/Escape)
  - Dialog supports scrolling for long disclaimers (Up/Down, Page Up/Page Down)
  - File must exist and be readable (validated during linting)

**Submenu Items** contain other menu items:

```toml
[menu.tools]
type = "submenu"
name = "System Tools"
description = "Various system utilities"
```

**Selector Items** allow users to choose from predefined options:

```toml
[menu.settings.theme]
type = "selector"
name = "Select Theme"
description = "Choose application theme"
install_key = "THEME"
options = ["dark", "light", "auto"]
default = "auto"
```

### Advanced Menu Features

#### Multiple Selection Items

For selecting multiple options from a list:

```toml
[menu.packages]
type = "multiple_selection"
name = "Select Packages"
description = "Choose packages to install"
install_key = "PACKAGES"
options = ["git", "vim", "tmux", "htop", "curl", "wget"]
default = ["git", "vim"]
```

#### Variable Substitution

You can use variables from selectors in your commands:

```toml
[menu.settings.compression]
type = "selector"
name = "Compression Format"
description = "Choose compression format for backups"
install_key = "COMPRESS_TYPE"
options = ["gzip", "bzip2", "xz"]
default = "gzip"

[menu.backup.create]
type = "action"
name = "Create Compressed Backup"
description = "Backup and compress config files"
command = "tar -c${COMPRESS_TYPE}vf backup-$(date +%Y%m%d).tar.${COMPRESS_TYPE} ~/.config/"
```

#### Custom Status Prefixes

You can customize how commands are displayed while running:

```toml
[menu.backup]
type = "action"
name = "Backup System"
description = "Create system backup"
command = "rsync -av /home /backup/"
nwiz_status_prefix = "Creating backup"
```

##### Shell Configuration

Specify which shell to use for executing commands:

```toml
[menu]
title = "My Menu"
shell = "/bin/zsh"  # Default is /bin/sh
```

#### Sudo Session Management

nwiz includes intelligent sudo session management that automatically adapts to your system's sudo configuration:

##### Automatic Detection (Recommended)

By default, nwiz auto-detects your system's sudo timeout and optimizes refresh timing:

```toml
[menu]
title = "System Manager"
description = "Automatically detects sudo timeout from system"
# No sudo_refresh_period specified - uses auto-detection
```

When auto-detection is used, nwiz:
1. Queries `/etc/sudoers` for the `timestamp_timeout` setting
2. Falls back to `sudo -V` output if needed
3. Uses the detected timeout minus 20 seconds for safety
4. Defaults to 4 minutes if detection fails

##### Manual Override

For specific requirements, you can override the automatic detection:

```toml
[menu]
title = "Custom System Manager"
description = "Manual sudo refresh configuration"
sudo_refresh_period = 180  # 3 minutes (30-3600 seconds allowed)
```

Common manual configurations:
- **High-security environments**: `sudo_refresh_period = 60` (1 minute)
- **Long-running tasks**: `sudo_refresh_period = 600` (10 minutes)  
- **Development systems**: `sudo_refresh_period = 120` (2 minutes)

#### ASCII Art Banner

You can add an ASCII art banner that displays at the top of your menu. The banner supports up to 10 lines and is defined as an array in the root menu section:

```toml
[menu]
title = "System Manager"
description = "Comprehensive system management"
ascii_art = [
    "███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗",
    "██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║",
    "███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║",
    "╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║",
    "███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║",
    "╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝"
]
```

The ASCII art appears above the menu items and adds visual branding to your interface. Keep each line under 80 characters for best display across different terminal sizes.

## Theming System

nwiz includes a comprehensive theming system that allows you to customize the appearance of your menus and interface. You can use built-in themes or create completely custom themes.

### Built-in Themes

nwiz comes with several built-in themes that you can use immediately. The default theme is **nocturne** (a purple gradient theme). Available themes are:

- **nocturne**: Default purple theme matching the Nocturne desktop environment branding
- **forest**: Green gradient theme inspired by nature
- **water**: Blue gradient theme with aquatic colors
- **nature**: Brown/earth-toned gradient theme
- **fire**: Red/orange gradient theme with warm colors
- **rainbow**: Colorful rainbow theme with vibrant colors spanning the full spectrum
- **greyscale**: Monochromatic theme with dark grey to light grey gradient

You can view all available themes with their color previews:

```bash
nwiz --show-themes
```

You can specify a built-in theme using the command line:

```bash
nwiz --theme nocturne
nwiz --theme forest
nwiz --theme water
nwiz --theme nature
nwiz --theme fire
nwiz --theme rainbow
nwiz --theme greyscale
```

### Custom Themes

For complete control over appearance, you can create a custom `theme.toml` file. The theme file allows you to customize colors for every interface element.

#### Creating a Custom Theme

Create a file called `theme.toml` with the following structure:

```toml
[theme]
name = "My Custom Theme"
description = "A personalized theme for my system"

# Menu colors
[colors.menu]
background = "#1a1a1a"
foreground = "#ffffff"
selected_background = "#3a3a3a"
selected_foreground = "#00ff00"
border = "#555555"
title = "#ffff00"
description = "#cccccc"

# Output viewer colors
[colors.output]
background = "#000000"
foreground = "#ffffff"
success = "#00ff00"
error = "#ff0000"
warning = "#ffaa00"
info = "#00aaff"
command = "#ff00ff"

# Status and UI elements
[colors.status]
running = "#ffaa00"
completed = "#00ff00"
failed = "#ff0000"
progress = "#00aaff"

# ASCII art and branding
[colors.branding]
ascii_art = "#00ffff"
header = "#ffff00"
footer = "#888888"
```

#### Color Format

Colors can be specified in several formats:

- **Hex colors**: `"#ff0000"` (red), `"#00ff00"` (green), `"#0000ff"` (blue)
- **RGB values**: `"rgb(255, 0, 0)"` for red
- **Named colors**: `"red"`, `"green"`, `"blue"`, `"yellow"`, `"cyan"`, `"magenta"`, `"white"`, `"black"`
- **Terminal colors**: `"terminal_red"`, `"terminal_green"`, etc. (uses terminal's color scheme)

#### Using Custom Themes

You can use your custom theme in several ways:

```bash
# Use a theme file by path
nwiz --theme /path/to/theme.toml

# Place theme.toml in the default config directory
# ~/.config/nwiz/theme.toml (will be loaded automatically)

# Use with custom config
nwiz --config /path/to/menu.toml --theme /path/to/custom-theme.toml
```

#### Theme Configuration Example

Here's a complete example of a custom dark theme:

```toml
[theme]
name = "Midnight Blue"
description = "A dark blue theme for night-time system administration"

[colors.menu]
background = "#0d1117"
foreground = "#c9d1d9"
selected_background = "#21262d"
selected_foreground = "#58a6ff"
border = "#30363d"
title = "#f0f6fc"
description = "#8b949e"

[colors.output]
background = "#010409"
foreground = "#c9d1d9"
success = "#238636"
error = "#da3633"
warning = "#bf8700"
info = "#1f6feb"
command = "#bc8cff"

[colors.status]
running = "#bf8700"
completed = "#238636"
failed = "#da3633"
progress = "#1f6feb"

[colors.branding]
ascii_art = "#58a6ff"
header = "#f0f6fc"
footer = "#6e7681"
```

### Theme Customization Tips

1. **Test with your content**: ASCII art and menu text should be easily readable
2. **Consider accessibility**: Ensure sufficient contrast between text and background colors
3. **Terminal compatibility**: Some terminals may not support all color formats
4. **Consistent palette**: Use a cohesive color scheme throughout your theme
5. **Brand alignment**: Match colors to your organization or system branding

### Exporting Built-in Themes

You can export any built-in theme to a TOML file for customization using the `--write-theme` option:

```bash
# Export default theme (nocturne)
nwiz --write-theme my-theme.toml

# Export specific built-in theme
nwiz -t rainbow --write-theme rainbow-custom.toml
nwiz -t greyscale --write-theme grey-theme.toml
```

This creates a complete theme.toml file that you can:
1. **Modify**: Edit the colors to create your custom theme
2. **Use**: Load with `nwiz --theme my-theme.toml`
3. **Share**: Distribute to others for consistent theming

The exported file contains all gradient colors, base colors, and UI element colors with proper hex values.

### Default Theme Location

If no theme is specified, nwiz will look for themes in this order:

1. Theme specified via `--theme` command line option
2. `~/.config/nwiz/theme.toml` (custom theme in config directory)
3. Built-in "nocturne" theme (default)

## Using the Menu Linter

The built-in linter helps validate your menu configuration files before using them. Run the linter with:

```bash
nwiz --lint menu.toml
```

The linter checks for:

- Correct TOML syntax
- Required fields for each item type
- Valid item types
- Proper hierarchy structure
- Circular references
- Duplicate item IDs

Example linter output:

```
Validating menu configuration: menu.toml
Warning: Item 'menu.tools.missing' has no command defined
Error: Unknown item type 'invalid' for item 'menu.broken'
Validation completed with 1 error(s) and 1 warning(s)
```

## Working with install.toml

The install.toml file is automatically created by nwiz to persist user selections from selector and multiple_selection menu items. This file acts as a configuration database that remembers user choices across sessions and makes them available to menu commands.

### File Location and Creation

When nwiz starts, it automatically creates install.toml if it doesn't exist. The default location is the same directory as your menu.toml file:

- If using default config: `~/.config/nwiz/install.toml`
- If using `--config /path/to/menu.toml`: install.toml is created in `/path/to/`
- If using `--install-config-dir /custom/path`: install.toml is created in `/custom/path/`

The file is created with default values from your menu configuration. All selector and multiple_selection items are automatically saved to install.toml:
- Selector items with a `default` value use that value
- Selector items without a default use the first option from their options list
- Multiple_selection items with `defaults` array use those values  
- Multiple_selection items without defaults start with an empty selection

### How install.toml Works

When you define a selector or multiple_selection item in your menu with an `install_key`, nwiz automatically:

1. Creates an entry in install.toml when the file is first generated
2. Updates the entry whenever the user makes a selection
3. Loads the saved value when the application starts
4. Makes the value available as a variable in menu commands

Example menu items that use install.toml:

```toml
# This selector's value is saved as "log_level" in install.toml
[menu.debug.level]
type = "selector"
name = "Log Level"
description = "Set application log verbosity"
install_key = "LOG_LEVEL"
options = ["error", "warning", "info", "debug"]
default = "info"

# This multiple selection's values are saved as "features" in install.toml
[menu.features.select]
type = "multiple_selection"
name = "Enable Features"
description = "Choose which features to enable"
install_key = "FEATURES"
options = ["logging", "metrics", "tracing", "profiling"]
default = ["logging", "metrics"]
```

### Structure of install.toml

After making selections, install.toml will look like this:

```toml
[selections]
log_level = "debug"              # From selector with install_key
features = ["logging", "metrics", "tracing"]  # From multiple_selection with install_key
```

Note that the keys in install.toml are automatically converted to lowercase. So `LOG_LEVEL` becomes `log_level` and `FEATURES` becomes `features`. If an item doesn't have an explicit `install_key`, the menu item's ID is used as the key.

### Using Saved Values in Commands

The values stored in install.toml are automatically available as environment variables in your menu commands. Variable names from install.toml are converted to uppercase when used in commands:

```toml
[menu.start.service]
type = "action"
name = "Start Service"
description = "Start service with saved configuration"
command = "myservice --log-level=${LOG_LEVEL} --features=${FEATURES}"
```

When this command runs, `${LOG_LEVEL}` is replaced with the value from install.toml (e.g., "debug"), and `${FEATURES}` is replaced with space-separated values (e.g., "logging metrics tracing").

### Reading Configuration in External Scripts

You can export install.toml values as environment variables for use in shell scripts:

```bash
# Export all values from install.toml as NWIZ_* variables
eval $(nwiz --config-options ~/.config/nwiz/install.toml)

# Now you can use them in your script
echo $NWIZ_LOG_LEVEL     # Outputs: debug
echo $NWIZ_FEATURES      # Outputs: logging metrics tracing

# Use in conditionals
if [[ "$NWIZ_LOG_LEVEL" == "debug" ]]; then
    echo "Debug mode enabled"
fi

# Loop through multiple values
for feature in $NWIZ_FEATURES; do
    echo "Enabling feature: $feature"
done
```

All variables are prefixed with `NWIZ_` to avoid conflicts with existing environment variables. Multiple selection values are space-separated.

### Manual Editing

You can manually edit install.toml if needed, but be aware that:

1. The file must maintain valid TOML syntax
2. Keys should be lowercase
3. Single values should be strings: `key = "value"`
4. Multiple values should be arrays: `key = ["value1", "value2"]`
5. Changes take effect the next time nwiz starts

### Validation and Recovery

If install.toml becomes corrupted or doesn't match the current menu structure, nwiz will automatically:

1. Detect the mismatch when starting
2. Backup and delete the invalid file
3. Create a new install.toml with default values from menu.toml
4. Display a message about the recreation

This ensures the application always starts successfully even if the configuration becomes invalid.

### Practical Example

Here's a complete example showing how menu items, install.toml, and commands work together:

```toml
# menu.toml
[menu]
title = "Database Manager"

[menu.config.db_type]
type = "selector"
name = "Database Type"
install_key = "DB_TYPE"
options = ["postgresql", "mysql", "sqlite"]
default = "postgresql"

[menu.config.db_host]
type = "selector"
name = "Database Host"
install_key = "DB_HOST"
options = ["localhost", "192.168.1.100", "db.example.com"]
default = "localhost"

[menu.backup.run]
type = "action"
name = "Backup Database"
command = """
case ${DB_TYPE} in
    postgresql) pg_dump -h ${DB_HOST} -d myapp > backup.sql ;;
    mysql) mysqldump -h ${DB_HOST} myapp > backup.sql ;;
    sqlite) cp /var/lib/myapp/db.sqlite backup.sqlite ;;
esac
"""
```

After selecting "mysql" and "192.168.1.100", install.toml contains:

```toml
[selections]
db_type = "mysql"
db_host = "192.168.1.100"
```

And the backup command will execute as:
```bash
mysqldump -h 192.168.1.100 myapp > backup.sql
```

## Practical Examples

### System Administration Menu

Here's a complete example for system administration tasks:

```toml
[menu]
title = "System Administration"
description = "Comprehensive system management"
shell = "/bin/bash"
sudo_refresh_period = 300  # 5-minute refresh for admin tasks
ascii_art = [
    "  ██████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗",
    " ██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║",
    " ███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║",
    " ╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║",
    " ███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║",
    " ╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝"
]

[menu.maintenance]
type = "submenu"
name = "Maintenance"
description = "System maintenance tasks"

[menu.maintenance.update]
type = "action"
name = "Update System"
description = "Update all packages"
command = "sudo apt update && sudo apt upgrade -y"
nwiz_status_prefix = "Updating system"

[menu.maintenance.clean]
type = "action"
name = "Clean System"
description = "Remove unnecessary packages"
command = "sudo apt autoremove -y && sudo apt autoclean"

[menu.backup]
type = "submenu"
name = "Backup"
description = "Backup operations"

[menu.backup.destination]
type = "selector"
name = "Backup Destination"
description = "Choose backup location"
install_key = "BACKUP_DEST"
options = ["/backup/local", "/mnt/nas/backup", "/media/usb/backup"]
default = "/backup/local"

[menu.backup.home]
type = "action"
name = "Backup Home Directory"
description = "Backup user home directory"
command = "rsync -av --progress /home/ ${BACKUP_DEST}/home/"

[menu.monitoring]
type = "submenu"
name = "System Monitoring"
description = "Monitor system resources"

[menu.monitoring.resources]
type = "action"
name = "Resource Usage"
description = "Show CPU, memory, and disk usage"
command = "./scripts/system-resources.sh"

[menu.monitoring.services]
type = "action"
name = "Service Status"
description = "Check critical services"
command = "./scripts/check-services.sh"
```

### Development Environment Setup

Example for setting up development environments:

```toml
[menu]
title = "Development Environment"
description = "Setup and manage development tools"

[menu.languages]
type = "multiple_selection"
name = "Select Languages"
description = "Choose programming languages to install"
install_key = "DEV_LANGUAGES"
options = ["python", "nodejs", "golang", "rust", "java"]
default = ["python", "nodejs"]

[menu.editors]
type = "selector"
name = "Primary Editor"
description = "Choose your main code editor"
install_key = "CODE_EDITOR"
options = ["vscode", "vim", "neovim", "emacs", "sublime"]
default = "vscode"

[menu.install]
type = "submenu"
name = "Installation"
description = "Install selected tools"

[menu.install.languages]
type = "action"
name = "Install Languages"
description = "Install selected programming languages"
command = """
for lang in ${DEV_LANGUAGES}; do
    case $lang in
        python) sudo apt install python3 python3-pip ;;
        nodejs) curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt install nodejs ;;
        golang) sudo snap install go --classic ;;
        rust) curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh ;;
        java) sudo apt install default-jdk ;;
    esac
done
"""

[menu.install.editor]
type = "action"
name = "Install Editor"
description = "Install selected code editor"
command = """
case ${CODE_EDITOR} in
    vscode) sudo snap install code --classic ;;
    vim) sudo apt install vim ;;
    neovim) sudo apt install neovim ;;
    emacs) sudo apt install emacs ;;
    sublime) sudo snap install sublime-text --classic ;;
esac
"""
```

### Complete Themed System Example

Here's an example that combines ASCII art, custom theming, and comprehensive functionality:

**theme.toml**:
```toml
[theme]
name = "Corporate Blue"
description = "Professional corporate theme"

[colors.menu]
background = "#002244"
foreground = "#ffffff"
selected_background = "#0056b3"
selected_foreground = "#ffffff"
border = "#4a90e2"
title = "#ffd700"
description = "#b3d9ff"

[colors.output]
background = "#001122"
foreground = "#e6f3ff"
success = "#28a745"
error = "#dc3545"
warning = "#ffc107"
info = "#17a2b8"
command = "#6f42c1"

[colors.branding]
ascii_art = "#4a90e2"
header = "#ffd700"
footer = "#6c757d"
```

**menu.toml**:
```toml
[menu]
title = "Corporate IT Management"
description = "Enterprise system administration portal"
shell = "/bin/bash"
ascii_art = [
    " ██████╗ ██████╗ ██████╗ ██████╗      ██╗████████╗",
    "██╔════╝██╔═══██╗██╔══██╗██╔══██╗     ██║╚══██╔══╝",
    "██║     ██║   ██║██████╔╝██████╔╝     ██║   ██║   ",
    "██║     ██║   ██║██╔══██╗██╔═══╝      ██║   ██║   ",
    "╚██████╗╚██████╔╝██║  ██║██║          ██║   ██║   ",
    " ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝          ╚═╝   ╚═╝   "
]

[menu.environment]
type = "selector"
name = "Target Environment"
description = "Select deployment environment"
install_key = "DEPLOY_ENV"
options = ["development", "staging", "production"]
default = "development"

[menu.services]
type = "multiple_selection"
name = "Services to Deploy"
description = "Choose which services to deploy"
install_key = "SERVICES"
options = ["web-server", "database", "cache", "queue", "monitoring"]
default = ["web-server", "database"]

[menu.deploy]
type = "action"
name = "Deploy Selected Services"
description = "Deploy services to target environment"
command = "deploy.sh --env=${DEPLOY_ENV} --services='${SERVICES}'"
nwiz_status_prefix = "Deploying to"
```

**Usage**:
```bash
# Run with the custom theme
nwiz --config corporate-menu.toml --theme theme.toml

# Or place both files in ~/.config/nwiz/ and run
nwiz
```

This example demonstrates how themes, ASCII art, configuration persistence, and variable substitution work together to create a professional, branded interface for system administration tasks.

## Batch Mode

nwiz supports batch mode for automated execution of all menu actions without user interaction. This is ideal for scripting, automated deployments, and CI/CD pipelines.

### Basic Batch Mode

Run all actions in sequence automatically:

```bash
# Execute all actions with default values
nwiz --batch

# Batch mode with custom configuration
nwiz --batch --config /path/to/menu.toml --no-sudo
```

In basic batch mode, nwiz:
1. Executes all action items in menu hierarchy order
2. Uses default values for selectors and multiple selections
3. Pauses between actions (configurable, default 2 seconds)
4. Displays progress with batch context (Action 1/5, Action 2/5, etc.)

### Batch Mode with Answer Files

Use TOML answer files to provide pre-configured values for selectors and multiple selections:

```bash
nwiz --batch --answer-file answers.toml
```

**Important**: The `--answer-file` parameter requires `--batch` to be specified. If `--answer-file` is used without `--batch`, it will be silently ignored.

#### Creating Answer Files

Answer files are TOML files that specify values for menu items with `install_key` attributes. The format mirrors the install.toml structure:

**answers.toml example**:
```toml
[install]
theme = "dark"
editor_type = "vim"
shell_type = "zsh"
dev_tools = ["git", "nodejs", "vim"]
project_features = ["logging", "metrics"]
backup_destination = "/backup/remote"
deploy_environment = "staging"
```

#### Answer File Structure Rules

1. **Section**: All values must be under the `[install]` section
2. **Key names**: Use lowercase versions of the `install_key` values from your menu
3. **Single values**: For selector items, use strings: `key = "value"`
4. **Multiple values**: For multiple_selection items, use arrays: `key = ["value1", "value2"]`
5. **Case conversion**: `install_key = "LOG_LEVEL"` becomes `log_level = "debug"` in the answer file

#### Example Menu → Answer File Mapping

**menu.toml**:
```toml
[menu.config.theme]
type = "selector"
name = "UI Theme"
install_key = "UI_THEME"
options = ["light", "dark", "auto"]
default = "auto"

[menu.config.languages]
type = "multiple_selection"
name = "Programming Languages"
install_key = "DEV_LANGUAGES"
options = ["python", "javascript", "golang", "rust"]
default = ["python"]
```

**answers.toml**:
```toml
[install]
ui_theme = "dark"           # selector: single string value
dev_languages = ["python", "javascript", "golang"]  # multiple_selection: array
```

### Batch Mode Configuration

You can create dedicated batch configuration files to control batch execution:

**batch-config.toml**:
```toml
[batch]
pause_between_actions = 3    # Seconds to pause between actions (default: 2)

[actions]
# Specify which actions to run (optional - defaults to all actions)
include = [
    "menu.install.packages",
    "menu.configure.system", 
    "menu.deploy.services"
]

# Or exclude specific actions
exclude = [
    "menu.dangerous.reset"
]
```

### Batch Mode Examples

#### Complete Development Environment Setup

**dev-menu.toml**:
```toml
[menu]
title = "Development Environment Setup"
description = "Automated development environment configuration"

[menu.config.editor]
type = "selector"
name = "Code Editor"
install_key = "CODE_EDITOR"
options = ["vscode", "vim", "neovim", "sublime"]
default = "vscode"

[menu.config.languages]
type = "multiple_selection"
name = "Programming Languages"
install_key = "LANGUAGES"
options = ["python", "nodejs", "golang", "rust", "java"]
default = ["python", "nodejs"]

[menu.config.tools]
type = "multiple_selection"
name = "Development Tools"
install_key = "DEV_TOOLS"
options = ["git", "docker", "kubernetes", "terraform"]
default = ["git"]

[menu.install.languages]
type = "action"
name = "Install Languages"
command = "./scripts/install-languages.sh"

[menu.install.editor]
type = "action"
name = "Install Editor"
command = "./scripts/install-editor.sh"

[menu.install.tools]
type = "action"
name = "Install Tools"
command = "./scripts/install-tools.sh"

[menu.configure.dotfiles]
type = "action"
name = "Configure Dotfiles"
command = "./scripts/setup-dotfiles.sh"
```

**dev-answers.toml**:
```toml
[install]
code_editor = "neovim"
languages = ["python", "nodejs", "golang", "rust"]
dev_tools = ["git", "docker", "kubernetes"]
```

**Usage**:
```bash
# Run with specific answers
nwiz --batch --answer-file dev-answers.toml --config dev-menu.toml

# Scripts can access the values:
# ./scripts/install-languages.sh uses $LANGUAGES
# ./scripts/install-editor.sh uses $CODE_EDITOR
# ./scripts/install-tools.sh uses $DEV_TOOLS
```

#### Server Deployment Example

**deploy-answers.toml**:
```toml
[install]
target_environment = "production"
services = ["web-server", "database", "cache", "monitoring"]
backup_enabled = "yes"
ssl_enabled = "yes"
```

```bash
# Automated deployment
nwiz --batch \
     --answer-file deploy-answers.toml \
     --config deployment-menu.toml \
     --log-file deployment-$(date +%Y%m%d).log
```

### Batch Mode Script Integration

Shell scripts can load and use batch mode values:

**install-script.sh**:
```bash
#!/bin/bash

# Load configuration from answer file or install.toml
eval $(nwiz --config-options install.toml)

echo "Setting up environment with:"
echo "  Editor: ${NWIZ_CODE_EDITOR:-vscode}"
echo "  Languages: ${NWIZ_LANGUAGES:-python nodejs}"
echo "  Tools: ${NWIZ_DEV_TOOLS:-git}"

# Use the values in your installation logic
for lang in $NWIZ_LANGUAGES; do
    echo "Installing $lang..."
    case $lang in
        python) install_python ;;
        nodejs) install_nodejs ;;
        golang) install_golang ;;
        rust) install_rust ;;
    esac
done

install_editor "$NWIZ_CODE_EDITOR"
```

### Batch Mode Best Practices

1. **Validation**: Test your answer files with normal interactive mode first
2. **Error Handling**: Design scripts to handle missing or invalid values gracefully
3. **Logging**: Use `--log-file` to capture full batch execution logs
4. **Idempotency**: Make commands safe to run multiple times
5. **Progress Feedback**: Use status prefixes and meaningful command output

```toml
[menu.deploy.app]
type = "action"
name = "Deploy Application"
command = "./scripts/deploy-app.sh"
nwiz_status_prefix = "Deploying application"
show_output = true  # Show output immediately in batch mode
```

### Validation and Testing

Test your batch configurations:

```bash
# Validate menu structure
nwiz --lint menu.toml

# Test with dry-run approach (if your scripts support it)
DRYRUN=true nwiz --batch --answer-file test-answers.toml

# Test interactively first
nwiz --config menu.toml  # Make selections manually
# Then copy resulting install.toml as your answer file
```

### Error Handling in Batch Mode

**Script example**:
```bash
#!/bin/bash
set -e  # Exit on first error

# Use proper error handling in your scripts
command1 || { echo "Command1 failed"; exit 1; }
command2 || { echo "Command2 failed"; exit 1; }
```


## Troubleshooting

### Common Issues

If the application fails to start with a terminal access error, ensure you're running in a proper terminal emulator, not through an IDE console or SSH without PTY allocation.

If menus don't load correctly, validate your menu.toml file using the linter:

```bash
nwiz --lint menu.toml
```

If commands fail with permission errors, ensure you either run nwiz with appropriate permissions or use sudo within your commands.

### Configuration File Locations

Default configuration locations:

- Menu configuration: `~/.config/nwiz/menu.toml`
- Install selections: `~/.config/nwiz/install.toml`
- Theme configuration: `~/.config/nwiz/theme.toml`

You can override these with command-line options.

### Debug Mode

For troubleshooting, you can see more detailed output by checking the console where you launched nwiz. Error messages and command outputs are displayed there.

## Best Practices

When creating menus, organize related items into submenus for better navigation. Use descriptive names and helpful descriptions for all menu items.

For commands that take a long time, provide feedback using the nwiz_status_prefix option. This helps users understand what's happening.

Always test your menu configurations with the linter before deployment. This catches errors early and ensures a smooth user experience.

Use variable substitution to make your menus flexible and reusable. Store user preferences in selectors and reference them in your commands.

For complex operations, consider breaking them into multiple menu items or creating scripts that the menu items call. This makes maintenance easier and allows for better error handling.

Remember that all commands run in a non-interactive shell by default. If you need user interaction, consider using expect scripts or similar tools.

## Conclusion

nwiz provides a powerful framework for creating interactive terminal menus. By combining menu configurations with the install.toml persistence system, you can create sophisticated installation wizards, system management tools, and configuration interfaces that remember user preferences across sessions.