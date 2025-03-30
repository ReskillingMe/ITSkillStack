#!/bin/bash
# Control-M Memory Deep Dive
PID=$(pgrep ctmag)
[ -z "$PID" ] && { echo "Control-M PID not found"; exit 1; }

OUTDIR="/tmp/ctl_mem_deepdive_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# 1. Process memory maps
pmap -x "$PID" > "$OUTDIR/pmap.txt"

# 2. Open files/handles
lsof -p "$PID" > "$OUTDIR/open_files.txt"

# 3. Java heap dump (if applicable)
if ps -p "$PID" -o cmd | grep -q "java"; then
    jmap -dump:live,format=b,file="$OUTDIR/heap.hprof" "$PID"
fi

# 4. Kernel allocations
sudo grep "ctmag" /proc/slabinfo > "$OUTDIR/kernel_slabs.txt"

echo "Deep dive data saved to: $OUTDIR"

