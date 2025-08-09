#!/bin/bash
# Load configuration from install.toml
eval $(nwiz --config-options demo/install.toml)

echo "[PROJECT] Creating new ${NWIZ_PROJECT_LANG:-javascript} project"
sleep 1
echo "[PROJECT] Setting up base project structure"
sleep 1

echo "=== Project Details ==="
echo "Language: ${NWIZ_PROJECT_LANG:-javascript}"
echo "Features: ${NWIZ_PROJECT_FEATURES:-none}"
echo ""

echo "[PROJECT] Creating project directory"
echo "Created: ./my-project/"
echo "Created: ./my-project/src/"

if [[ "${NWIZ_PROJECT_FEATURES}" == *"testing"* ]]; then
    echo "Created: ./my-project/tests/"
fi

if [[ "${NWIZ_PROJECT_FEATURES}" == *"docs"* ]]; then
    echo "Created: ./my-project/docs/"
fi

if [[ "${NWIZ_PROJECT_FEATURES}" == *"docker"* ]]; then
    echo "Created: ./my-project/Dockerfile"
fi

echo "[PROJECT] Project created successfully"
echo "Your ${NWIZ_PROJECT_LANG:-javascript} project is ready for development!"
sleep 1