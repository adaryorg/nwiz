#!/bin/bash
# Load configuration from install.toml
eval $(nwiz --config-options demo/install.toml)
echo "[CONFIG] Loading configuration options from install.toml"
sleep 1

# Use nwiz to read configuration options
echo "[CONFIG] Reading persistent configuration"
echo "Loading saved configuration options..."
echo ""

# Read configuration using nwiz
nwiz --config-options demo/install.toml 2>/dev/null | while read -r line; do
    if [[ $line == export* ]]; then
        echo "Found saved option: ${line#export }"
    fi
done

echo ""
echo "[CONFIG] Displaying current environment variables"
sleep 1

# Show relevant environment variables
echo "=== Current Configuration Variables ==="
env | grep -E '^NWIZ_' | sort || echo "No NWIZ configuration variables currently set"

echo ""
echo "[CONFIG] Configuration demo completed"
echo ""
echo "This demonstrates how nwiz can persist configuration between sessions"
echo "using the install.toml file and --config-options feature."
sleep 1