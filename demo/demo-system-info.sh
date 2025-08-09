#!/bin/bash
echo "[SYSTEM] Gathering system information"
sleep 1
echo "=== System Information ==="
echo "Operating System: $(uname -s)"
echo "Kernel Version: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Hostname: $(hostname)"
echo "[SYSTEM] Checking system resources"
sleep 1
echo "=== System Resources ==="
echo "CPU Cores: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Disk Usage: $(df -h / | tail -1 | awk '{print $5}')"
echo "[SYSTEM] Information gathered successfully"
echo ""
echo "System information collection complete!"
sleep 1