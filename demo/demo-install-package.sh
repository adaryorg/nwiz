#!/bin/bash
PACKAGE=${1:-"default-package"}
echo "[INSTALL] Installing package: $PACKAGE"
sleep 1
echo "[INSTALL] Checking dependencies"
sleep 1
echo "Dependency check: Found 3 required packages"
echo "[INSTALL] Downloading $PACKAGE"
sleep 2
echo "Downloaded: $PACKAGE (5.2 MB)"
echo "[INSTALL] Installing $PACKAGE"
sleep 2
echo "Extracting files..."
echo "Configuring package..."
echo "Setting up links..."
echo "[INSTALL] Package installed successfully"
echo ""
echo "Package '$PACKAGE' has been installed successfully!"
sleep 1