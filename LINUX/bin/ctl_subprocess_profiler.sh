#!/bin/bash
# Control-M Subprocess Memory Profiler
MAIN_PID=$(pgrep ctmag)
[ -z "$MAIN_PID" ] && { echo "Control-M PID not found"; exit 1; }

OUTDIR="/tmp/ctl_subprocesses_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# 1. Get all child PIDs
CHILD_PIDS=$(pgrep -P "$MAIN_PID")

# 2. Profile each subprocess
for PID in $CHILD_PIDS; do
    # Memory map
    pmap -x "$PID" > "$OUTDIR/pmap_${PID}.txt"

    # System calls (sample for 5 seconds)
    timeout 5 strace -p "$PID" -c -o "$OUTDIR/strace_${PID}.txt" 2>&1 &

    # Open files
    lsof -p "$PID" > "$OUTDIR/lsof_${PID}.txt"
done

# 3. Generate consolidated report
{
    echo "Subprocess Memory Report - $(date)"
    echo "================================="
    for PID in $CHILD_PIDS; do
        RSS=$(ps -p "$PID" -o rss=)
        echo -e "\nPID: $PID (RSS: ${RSS} KB)"
        echo "Top memory regions:"
        grep -E "total|Kbytes" "$OUTDIR/pmap_${PID}.txt"
        echo "System call summary:"
        tail -n 10 "$OUTDIR/strace_${PID}.txt"
    done
} > "$OUTDIR/subprocess_report.txt"

echo "Subprocess analysis saved to: $OUTDIR"

