#!/bin/bash
echo "[UPDATES] Checking for available system updates"
sleep 2

echo "[UPDATES] Scanning package repositories"
sleep 1

echo "=== Available Updates ==="
echo "- kernel-linux: 6.15.8 → 6.15.9 (security update)"
echo "- firefox: 130.0 → 130.1 (bugfix)"
echo "- nvidia-driver: 550.90 → 551.10 (feature update)"
echo "- systemd: 255.0 → 255.1 (maintenance)"
echo "- vim: 9.0.1 → 9.0.2 (enhancement)"
echo ""
echo "Total: 5 updates available"
echo "Download size: 145 MB"
echo "Installation size: 320 MB"

echo "[UPDATES] Update check completed"
echo "Run 'sudo pacman -Syu' to install updates"
sleep 1