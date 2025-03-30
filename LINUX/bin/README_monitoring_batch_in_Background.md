# Control-M Agent Memory Monitoring in Batch/Background Mode

## Table of Contents
1. [Background Monitoring Options](#background-monitoring-options)
2. [Systemd Service Setup](#systemd-service-setup-recommended)
3. [nohup Method](#nohup-method-simple)
4. [tmux/screen Method](#tmuxscreen-method-interactive)
5. [Cron Job Method](#cron-job-method-scheduled)
6. [Verification & Log Management](#verification--log-management)

---

## Background Monitoring Options

### Systemd Service Setup (Recommended)
Most robust method for production environments with auto-restart capabilities.

```bash
# 1. Create the service file
sudo tee /etc/systemd/system/ctm_mem_monitor.service <<'EOF'
[Unit]
Description=Control-M Agent Memory Monitor
After=network.target

[Service]
User=root
ExecStart=/bin/bash -c 'while true; do echo "$(date) | $(ps -p $(pgrep ctmag) -o %%mem,rss,vsz,cmd)" >> /var/log/ctm_mem_monitor.log; sleep 300; done'
Restart=always
RestartSec=60s

[Install]
WantedBy=multi-user.target
EOF

# 2. Enable and start
sudo systemctl daemon-reload
sudo systemctl enable ctm_mem_monitor
sudo systemctl start ctm_mem_monitor


Key Features:

Automatic restart if the script fails

Logs to /var/log/ with proper rotation

Persistent across reboots

nohup Method (Simple)
Basic method that survives SSH disconnects but lacks monitoring.

    nohup bash -c '
        while true; do
        echo "$(date) | $(ps -p $(pgrep ctmag) -o %mem,rss,vsz,cmd)" >> /tmp/ctm_mem_monitor.log
        sleep 300
    done
    ' > /dev/null 2>&1 &

Pros:

Quick to implement

No dependencies

Cons:

Harder to stop/restart

No automatic recovery

tmux/screen Method (Interactive)
Best for temporary debugging with manual reattachment capability.


# Install tmux if needed
sudo yum install tmux -y  # OL9/RHEL

# Start session
tmux new -s ctm_monitor

# Run monitor inside tmux
while true; do
    echo "$(date) | $(ps -p $(pgrep ctmag) -o %mem,rss,vsz,cmd)" >> /tmp/ctm_mem.log
    sleep 300
done

# Detach: Ctrl+B then D
# Reattach: tmux attach -t ctm_monitor


Cron Job Method (Scheduled)
For periodic checks rather than continuous monitoring.

# Add to crontab (runs every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * ps -p \$(pgrep ctmag) -o \%mem,rss,vsz,cmd | awk -v date=\"\$(date)\" '{print date, \$0}' >> /var/log/ctm_mem_cron.log") | crontab -


Verification & Log Management
Check Running Monitor

# For systemd
sudo systemctl status ctm_mem_monitor

# For nohup/tmux
ps aux | grep "[c]tm_mem_monitor"


Log Rotation

    # Configure logrotate (systemd)
sudo tee /etc/logrotate.d/ctm_mem_monitor <<'EOF'
/var/log/ctm_mem_monitor.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        systemctl restart ctm_mem_monitor
    endscript
}
EOF


Stop Monitoring

# Systemd
sudo systemctl stop ctm_mem_monitor

# nohup
pkill -f "ctm_mem_monitor"

# tmux
tmux kill-session -t ctm_monitor

# Cron
crontab -e  # Remove the entry



Recommended Approach
Use Case	Best Method
Production servers	Systemd service
Temporary debugging	tmux
Legacy systems	nohup
Compliance/auditing	Cron job
For long-term monitoring, the systemd service is strongly recommended due to:

Built-in logging

Automatic restarts

Integration with system tools

Copy

This Markdown file provides a complete guide with copy-paste ready commands for all major background monitoring methods. Save it as `README.md` in your monitoring scripts directory.


