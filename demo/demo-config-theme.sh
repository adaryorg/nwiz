#!/bin/bash
# Load configuration from install.toml
eval $(nwiz --config-options demo/install.toml)

SELECTED_THEME=${NWIZ_THEME:-"default"}
echo "[THEME] Applying theme: $SELECTED_THEME"
sleep 1
echo "[THEME] Backing up current configuration"
sleep 1
echo "Created backup: ~/.config/theme.backup"
echo "[THEME] Loading theme configuration"
sleep 1
echo "Loading color schemes..."
echo "Loading font settings..."
echo "Loading window decorations..."
echo "[THEME] Applying theme settings"
sleep 2
echo "Applied colors: $SELECTED_THEME palette"
echo "Applied fonts: $SELECTED_THEME typeface"
echo "Applied decorations: $SELECTED_THEME style"
echo "[THEME] Theme applied successfully"
echo ""
echo "Theme '$SELECTED_THEME' has been applied!"
echo "Restart applications to see all changes."
sleep 1