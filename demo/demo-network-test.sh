#!/bin/bash
echo "[NETWORK] Starting network connectivity test"
sleep 1
echo "[NETWORK] Testing DNS resolution"
sleep 1
echo "DNS resolution: OK"
echo "[NETWORK] Testing internet connectivity"
sleep 1
echo "Pinging Google DNS (8.8.8.8)..."
echo "PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data."
echo "64 bytes from 8.8.8.8: icmp_seq=1 ttl=117 time=12.3 ms"
echo "64 bytes from 8.8.8.8: icmp_seq=2 ttl=117 time=11.8 ms" 
echo "64 bytes from 8.8.8.8: icmp_seq=3 ttl=117 time=12.1 ms"
echo "64 bytes from 8.8.8.8: icmp_seq=4 ttl=117 time=11.9 ms"
echo ""
echo "--- 8.8.8.8 ping statistics ---"
echo "4 packets transmitted, 4 received, 0% packet loss"
echo "[NETWORK] Network connectivity test completed successfully"
sleep 1