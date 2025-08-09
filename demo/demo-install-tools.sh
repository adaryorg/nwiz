#!/bin/bash
# Load configuration from install.toml
eval $(nwiz --config-options demo/install.toml)

echo "[INSTALL] Starting tool installation"
echo "Installing selected tools: ${NWIZ_DEV_TOOLS}"
sleep 1

# Install each selected tool
if [ -n "${NWIZ_DEV_TOOLS}" ]; then
    for tool in ${NWIZ_DEV_TOOLS}; do
        ./demo/demo-install-package.sh "$tool"
    done
else
    echo "No tools selected for installation"
fi

echo "[INSTALL] Tool installation completed"
sleep 1