#!/bin/bash
# ==============================================
# Control-M Memory Leak Troubleshooting Script
# Checks: Process memory, kernel params, security tools
# Usage: sudo ./ctl_mem_troubleshoot.sh [PID]
#
# Run against Control-M PID
# sudo ./ctl_mem_troubleshoot.sh $(pgrep ctmag)
#
# For Java-based agents, analyze heap dump with:
# jhat /tmp/ctl_mem_diagnostics_*/ctl_mem_heap.hprof
#
# ==============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if PID is provided
if [ -z "$1" ]; then
    echo -e "${RED}ERROR: Please specify Control-M PID.${NC}"
    echo "Example: sudo ./ctl_mem_troubleshoot.sh \$(pgrep ctmag)"
    exit 1
fi
PID=$1

# Output directory
OUTDIR="/tmp/ctl_mem_diagnostics_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# ==============================================
# 1. System Overview
# ==============================================
echo -e "${YELLOW}[1] System Overview${NC}" | tee "$OUTDIR/1_system_overview.txt"
{
    echo "---- Hostname ----"
    hostname
    echo -e "\n---- OS Version ----"
    cat /etc/os-release
    echo -e "\n---- Uptime ----"
    uptime
    echo -e "\n---- Kernel Version ----"
    uname -a
} | tee -a "$OUTDIR/1_system_overview.txt"

# ==============================================
# 2. Process Memory Analysis
# ==============================================
echo -e "${YELLOW}[2] Process Memory Analysis (PID: $PID)${NC}" | tee "$OUTDIR/2_process_memory.txt"
{
    echo "---- Control-M Process ----"
    ps -p "$PID" -o pid,ppid,%cpu,%mem,rss,vsz,cmd
    echo -e "\n---- Memory Trends (RSS in KB) ----"
    for i in {1..5}; do
        ps -p "$PID" -o rss= | awk -v date="$(date +'%H:%M:%S')" '{print date, $1}'
        sleep 2
    done
    echo -e "\n---- Memory Maps ----"
    pmap -x "$PID" | head -n 20
    echo -e "\n---- Open Files ----"
    lsof -p "$PID" | awk '{print $NF}' | grep -E "\.so|\.log" | sort | uniq -c | head -n 10
} | tee -a "$OUTDIR/2_process_memory.txt"

# ==============================================
# 3. Security Tool Checks
# ==============================================
echo -e "${YELLOW}[3] Security Tool Analysis${NC}" | tee "$OUTDIR/3_security_tools.txt"
{
    # CrowdStrike
    echo "---- CrowdStrike Status ----"
    if systemctl list-units | grep -q falcon-sensor; then
        sudo /opt/CrowdStrike/falconctl -g --aid | tee -a "$OUTDIR/crowdstrike_status.txt"
        echo -e "\n---- Exclusions ----"
        sudo grep -r "exclude" /etc/crowdstrike/*
    else
        echo "CrowdStrike not installed"
    fi

    # Tanium
    echo -e "\n---- Tanium Status ----"
    if systemctl list-units | grep -q tanium; then
        sudo taniumcli status | tee -a "$OUTDIR/tanium_status.txt"
        echo -e "\n---- Process Scans ----"
        sudo grep -i "procscan" /var/log/tanium/*.log | tail -n 5
    else
        echo "Tanium not installed"
    fi
} | tee -a "$OUTDIR/3_security_tools.txt"

# ==============================================
# 4. Kernel & Memory Diagnostics
# ==============================================
echo -e "${YELLOW}[4] Kernel Diagnostics${NC}" | tee "$OUTDIR/4_kernel_diagnostics.txt"
{
    echo "---- Kernel Parameters ----"
    sysctl -a | grep -E "vm.dirty|kernel.shm|kernel.yama" | grep -v "^net\."

    echo -e "\n---- OOM Events ----"
    dmesg | grep -i "oom\|kill" | tail -n 5

    echo -e "\n---- Slab Memory ----"
    sudo slabtop -o -s c | head -n 10

    echo -e "\n---- Kernel Modules ----"
    lsmod | grep -E "falcon|tanium" || echo "No security modules loaded"
} | tee -a "$OUTDIR/4_kernel_diagnostics.txt"

# ==============================================
# 5. Control-M Specific Checks
# ==============================================
echo -e "${YELLOW}[5] Control-M Configuration${NC}" | tee "$OUTDIR/5_controlm_config.txt"
{
    echo "---- Agent Parameters ----"
    grep -E "MEMORY_LIMIT|MAX_CONCURRENT_JOBS" "$CONTROLM/ctm_agent/agent_parm.txt" 2>/dev/null || echo "agent_parm.txt not found"

    echo -e "\n---- Job Output Directory ----"
    du -sh "$CONTROLM/ctm_agent/jobout" 2>/dev/null || echo "jobout directory not found"

    echo -e "\n---- Active Jobs ----"
    ctmpsm -LISTALL 2>/dev/null | head -n 5 || echo "Control-M CLI not available"
} | tee -a "$OUTDIR/5_controlm_config.txt"

# ==============================================
# 6. Heap Dump (Java-based agents)
# ==============================================
if ps -p "$PID" -o cmd | grep -q "java"; then
    echo -e "${YELLOW}[6] Java Heap Dump${NC}"
    sudo -u controlm jmap -dump:live,format=b,file="$OUTDIR/ctl_mem_heap.hprof" "$PID" 2>/dev/null && \
        echo "Heap dump saved to $OUTDIR/ctl_mem_heap.hprof" || \
        echo "Failed to capture heap dump (not Java?)"
fi

# ==============================================
# Final Report
# ==============================================
echo -e "${GREEN}\n=== Troubleshooting Complete ===${NC}"
echo -e "Diagnostic data saved to: ${YELLOW}$OUTDIR${NC}"
echo -e "Key files:"
ls -lh "$OUTDIR"/*.txt

