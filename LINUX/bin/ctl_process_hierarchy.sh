#!/bin/bash
# Control-M Process Hierarchy with Memory Usage
OUTDIR="/tmp/ctl_mem_hierarchy_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# 1. Get all Control-M related PIDs
CTL_PIDS=$(pgrep -f "ctmag|ctmrm|ctm_agent")

# 2. Generate process tree with memory
for PID in $CTL_PIDS; do
    ps -p "$PID" -o pid,ppid,user,%mem,%cpu,rss,vsz,cmd --no-headers >> "$OUTDIR/process_list.txt"
    pstree -p "$PID" -s -n >> "$OUTDIR/process_tree.txt"
done

# 3. Group by memory ranges (in KB)
awk 'BEGIN {print "PID\tPPID\tUSER\t%MEM\tRSS(KB)\tVSZ(KB)\tCMD" > "'"$OUTDIR/mem_groups.txt"'"}
     NR>1 {rss=$6;
           if (rss<10240) group="0-10MB";
           else if (rss<51200) group="10-50MB";
           else if (rss<102400) group="50-100MB";
           else group="100MB+";
           print $0 >> "'"$OUTDIR/"'"group".txt"}' "$OUTDIR/process_list.txt"

echo "Report generated: $OUTDIR/mem_groups.txt"

