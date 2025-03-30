#!/bin/bash
# Control-M Memory Trend Analysis
DURATION_MIN=30  # Monitoring duration
INTERVAL_SEC=10  # Sampling interval
OUTDIR="/tmp/ctl_mem_trend_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# Header for CSV
echo "Timestamp,PID,PPID,Group,RSS(KB),%MEM,Command" > "$OUTDIR/mem_trend.csv"

# Monitoring loop
for ((i=0; i<$((DURATION_MIN*60/INTERVAL_SEC)); i++)); do
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    ps -eo pid,ppid,%mem,rss,cmd --sort=-rss | grep -E "ctmag|ctmrm" | while read -r line; do
        PID=$(echo "$line" | awk '{print $1}')
        RSS=$(echo "$line" | awk '{print $4}')

        # Classify by RSS
        if [ "$RSS" -lt 10240 ]; then
            GROUP="0-10MB"
        elif [ "$RSS" -lt 51200 ]; then
            GROUP="10-50MB"
        elif [ "$RSS" -lt 102400 ]; then
            GROUP="50-100MB"
        else
            GROUP="100MB+"
        fi

        echo "$TIMESTAMP,$line,$GROUP" | awk '{OFS=","; print $1,$2,$3,$7,$4,$5,$6}' >> "$OUTDIR/mem_trend.csv"
    done
    sleep "$INTERVAL_SEC"
done

# Generate summary
awk -F, '{print $4}' "$OUTDIR/mem_trend.csv" | sort | uniq -c > "$OUTDIR/mem_group_summary.txt"

echo "Trend data saved to: $OUTDIR/mem_trend.csv"

