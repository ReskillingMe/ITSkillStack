#!/bin/bash
# Control-M Stability Validator
LOG="/tmp/ctl_validation_$(date +%Y%m%d).log"

{
    echo "=== Validation Started at $(date) ==="

    # 1. Memory stability check
    for i in {1..12}; do
        echo "[$(date +%H:%M)] RSS: $(ps -p $(pgrep ctmag) -o rss=) KB"
        sleep 300  # 5-minute intervals
    done

    # 2. Security tool exclusions
    if systemctl is-active falcon-sensor; then
        echo "CrowdStrike Exclusions:"
        sudo /opt/CrowdStrike/falconctl -g --tags=ExclusionList
    fi

    # 3. Kernel errors
    echo -e "\nLast 10 Kernel Errors:"
    dmesg | tail -n 10 | grep -i "error\|fail"
} | tee "$LOG"

echo "Validation log saved to: $LOG"


