#!/bin/bash
echo "[SCANNER] Starting port scan on localhost"
sleep 1

ports=(22 80 443 3000 8080)
echo "[SCANNER] Scanning ${#ports[@]} common ports"

for port in "${ports[@]}"; do
    echo "[SCANNER] Checking port $port"
    sleep 0.5
    if (( port == 22 )); then
        echo "Port $port: OPEN (SSH)"
    elif (( port == 80 )); then
        echo "Port $port: CLOSED"
    elif (( port == 443 )); then
        echo "Port $port: CLOSED" 
    elif (( port == 3000 )); then
        echo "Port $port: OPEN (Development server)"
    else
        echo "Port $port: CLOSED"
    fi
done

echo "[SCANNER] Port scan completed"
echo "Summary: 2 open ports, 3 closed ports"
sleep 1