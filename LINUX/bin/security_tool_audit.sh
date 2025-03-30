#!/bin/bash
# Security Tool Audit Script
OUTDIR="/tmp/security_audit_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# 1. CrowdStrike checks
if systemctl is-active falcon-sensor; then
    sudo /opt/CrowdStrike/falconctl -g --aid > "$OUTDIR/crowdstrike_config.txt"
    sudo grep -r "exclude" /etc/crowdstrike/ >> "$OUTDIR/crowdstrike_exclusions.txt"
fi

# 2. Tanium checks
if systemctl is-active tanium; then
    sudo taniumcli status > "$OUTDIR/tanium_status.txt"
    sudo grep -i "procscan" /var/log/tanium/*.log >> "$OUTDIR/tanium_scans.log"
fi

# 3. SELinux/AppArmor
sudo getenforce > "$OUTDIR/selinux_status.txt"
sudo aa-status > "$OUTDIR/apparmor_status.txt"

echo "Security audit saved to: $OUTDIR"

