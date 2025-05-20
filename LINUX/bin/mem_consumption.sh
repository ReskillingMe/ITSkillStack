#!/bin/bash

echo "Locale-archives allocated in memory for all processes:"

# Iterate over each process and check its memory mappings
for pid in $(ps -e -o pid --no-header); do
    if grep -q "locale-archive" /proc/$pid/maps 2>/dev/null; then
        echo "Process ID: $pid"
        pmap -x $pid | grep locale-archive
        echo "-----------------------------"
    fi
done
