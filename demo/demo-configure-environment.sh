#!/bin/bash
# Load configuration from install.toml
eval $(nwiz --config-options demo/install.toml)

echo "[ENV] Configuring development environment"
sleep 1
echo "[ENV] Applying selected preferences"
sleep 1

echo "=== Environment Configuration ==="
echo "Selected Shell: ${NWIZ_SHELL_TYPE:-bash}"
echo "Selected Editor: ${NWIZ_EDITOR_TYPE:-vim}"
echo ""

echo "[ENV] Setting up shell configuration"
sleep 1
echo "Configured ${NWIZ_SHELL_TYPE:-bash} with custom settings"

echo "[ENV] Setting up editor configuration"
sleep 1
echo "Configured ${NWIZ_EDITOR_TYPE:-vim} with development plugins"

echo "[ENV] Environment configuration completed successfully"
echo "Your development environment is ready!"
sleep 1