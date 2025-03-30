#!/bin/bash
# System Memory Profiler - Captures top consumers and trends
OUTDIR="/tmp/mem_profile_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# 1. Top memory processes (5-minute interval)
for i in {1..6}; do
    ps -eo pid,ppid,%mem,%cpu,rss,vsz,cmd --sort=-%mem | head -n 10 >> "$OUTDIR/top_mem.log"
    sleep 60
done

# 2. Kernel slab memory
sudo slabtop -o -s c > "$OUTDIR/slab_mem.log"

# 3. Shared memory (Control-M uses heavily)
ipcs -m >> "$OUTDIR/shared_mem.log"

# 4. OOM killer history
dmesg | grep -i "oom\|kill" > "$OUTDIR/oom_events.log"

echo "Memory profile saved to: $OUTDIR"

