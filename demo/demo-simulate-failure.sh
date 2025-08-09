#!/bin/bash
echo "[FAILURE] Starting potentially failing operation"
sleep 1
echo "[FAILURE] Checking prerequisites"
sleep 1
echo "Prerequisite check: OK"
echo "[FAILURE] Initializing process"
sleep 2
echo "Process initialized successfully"
echo "[FAILURE] Executing critical operation"
sleep 2
echo "ERROR: Critical operation failed!"
echo "Reason: Simulated failure for demo purposes"
echo ""
echo "This demonstrates how nwiz handles command failures."
echo "The status will show as 'Failed' in the menu."
exit 1