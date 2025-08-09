#!/bin/bash
echo "[VERBOSE] Generating large amount of output"
sleep 1

for i in {1..50}; do
    echo "Output line $i - This is a demonstration of scrollable output in nwiz"
    sleep 0.1
done

echo "[VERBOSE] Verbose output generation complete"
echo ""
echo "This demonstrates how nwiz handles large output with scrolling"
sleep 1