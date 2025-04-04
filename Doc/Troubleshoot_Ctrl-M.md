# Control-M High Memory Consumption After Tanium Client Update on OEL 9

## Root Cause Analysis
The issue appears to be a conflict between:
1. The updated Tanium client (security agent)
2. Control-M workload automation processes
3. OEL 9 kernel changes

This combination is causing abnormal memory growth in Control-M processes, eventually leading to kernel panics.

## Immediate Mitigation Steps

### 1. Isolate the Problem
```bash
# Identify affected Control-M processes
ps -eo pid,user,%mem,cmd --sort=-%mem | grep -E 'ctm|ControlM'

# Check for Tanium interactions
sudo strace -p <Control-M_PID> -e trace=open,read,write 2>&1 | grep tanium
```

### 2. Temporary Workarounds
```bash
# Option A: Limit Control-M memory via cgroups
sudo mkdir /sys/fs/cgroup/memory/ctm_limit
echo $((4 * 1024 * 1024 * 1024)) > /sys/fs/cgroup/memory/ctm_limit/memory.limit_in_bytes
for pid in $(pgrep -f "ctm"); do echo $pid >> /sys/fs/cgroup/memory/ctm_limit/tasks; done

# Option B: Adjust Tanium scanning exclusions
sudo vi /opt/Tanium/TaniumClient/config.ini
```
Add:
```ini
[Exclusions]
Path=/opt/ControlM/
Process=ctm*
```

## Long-Term Solutions

### 1. Tanium Configuration Adjustments
```bash
# Reduce scan frequency for Control-M directories
sudo vi /opt/Tanium/TaniumClient/tanium.policy
```
Add exclusions:
```json
{
  "exclusions": [
    {
      "path": "/opt/ControlM/**",
      "type": "path"
    },
    {
      "process_name": "ctm*",
      "type": "process"
    }
  ]
}
```

### 2. Control-M Optimization
```bash
# Adjust Control-M agent memory settings (location varies)
sudo vi /opt/ControlM/Server/ctm_server.cfg
```
Add/modify:
```
MAX_MEMORY=4096
GARBAGE_COLLECTION_INTERVAL=30
```

### 3. Kernel Parameter Tuning
```bash
# Add to /etc/sysctl.conf
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
vm.swappiness = 10
kernel.panic_on_oom = 0

# Apply changes
sudo sysctl -p
```

## Diagnostic Data to Collect

```bash
# 1. Memory usage timeline
pidstat -r -p $(pgrep -f "ctm") 5 60 > ctm_mem.log

# 2. Tanium-ControM interactions
sudo opensnoop -n ctm | grep tanium

# 3. Kernel slab info
sudo slabtop -o > slabinfo_before_after.log

# 4. OOM killer history
sudo grep -i 'kill' /var/log/messages*
```

## Vendor Coordination

1. **Contact Tanium Support** with:
   - Policy configuration files
   - `/opt/Tanium/TaniumClient/logs/*`
   - Output from `sudo taniumcli getcore`

2. **Contact BMC Support** with:
   - Control-M server logs
   - Memory usage logs (`ctm_mem.log`)
   - Core dumps (if generated)

Would you like me to provide specific commands to:
1. Generate memory leak reports for Control-M?
2. Create a systemtap script to trace Tanium-ControM interactions?
3. Develop a rolling back procedure for the Tanium update?

# Generating Memory Leak Reports for Control-M on OEL 9

## 1. Real-Time Memory Monitoring Setup

### Continuous Memory Logging
```bash
# Create monitoring script
sudo tee /usr/local/bin/monitor_ctm_mem.sh <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/ctm_mem_$(date +%Y%m%d).log"
echo "Timestamp, PID, RSS (KB), %MEM, Command" > $LOG_FILE
while true; do
    ps -eo pid,rss,%mem,cmd --sort=-rss | grep -E '[c]tm|[C]ontrolM' | \
    while read -r line; do
        echo "$(date '+%Y-%m-%d %H:%M:%S'), $line" >> $LOG_FILE
    done
    sleep 30
done
EOF

# Make executable and run as service
sudo chmod +x /usr/local/bin/monitor_ctm_mem.sh
sudo tee /etc/systemd/system/ctm_mem_monitor.service <<EOF
[Unit]
Description=Control-M Memory Monitor

[Service]
ExecStart=/usr/local/bin/monitor_ctm_mem.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start ctm_mem_monitor
```

## 2. Advanced Memory Analysis Tools

### Valgrind Memory Profiling (Requires Service Restart)
```bash
# Install valgrind if needed
sudo dnf install valgrind -y

# Capture memory leaks (run against Control-M executable)
sudo pkill ctm  # Stop running processes first
sudo valgrind --leak-check=full --show-leak-kinds=all --log-file=/var/log/ctm_valgrind.log /opt/ControlM/server/ctm_server

# For long-running analysis:
sudo valgrind --tool=memcheck --trace-children=yes --track-origins=yes --leak-check=full --log-file=/var/log/ctm_valgrind.log /opt/ControlM/server/ctm_server
```

### GDB Heap Analysis
```bash
# Install debug symbols first (if available)
sudo debuginfo-install ControlM

# Attach to running process
CTM_PID=$(pgrep -f "ctm_server")
sudo gdb -p $CTM_PID -ex "set pagination off" -ex "malloc_info 0 /tmp/ctm_heap.xml" -ex "detach" -ex "quit"

# Analyze heap output
sudo xmlstarlet sel -t -v "//allocated" /tmp/ctm_heap.xml | sort -n | tail -20
```

## 3. Kernel-Level Memory Tracking

### SystemTap Script for Memory Allocation
```bash
# Install systemtap
sudo dnf install systemtap kernel-devel-$(uname -r) -y

# Create allocation tracker
sudo tee /tmp/ctm_mem.stp <<'EOF'
probe process("/opt/ControlM/server/ctm_server").function("*malloc*") {
    printf("%s[%d] allocated %d bytes at %p\n", execname(), pid(), $size, $return)
}
probe process("/opt/ControlM/server/ctm_server").function("*free*") {
    printf("%s[%d] freed memory at %p\n", execname(), pid(), $mem)
}
EOF

# Run monitoring (CTRL+C to stop)
sudo stap -v /tmp/ctm_mem.stp > /var/log/ctm_allocations.log
```

### PMAP Analysis
```bash
# Periodic pmap snapshots
sudo mkdir /var/log/ctm_pmaps
watch -n 300 "pmap -x \$(pgrep -f 'ctm_server') > /var/log/ctm_pmaps/pmap_\$(date +%s).log"
```

## 4. Generating the Memory Leak Report

### Compile Data into Report
```bash
# Create analysis script
sudo tee /usr/local/bin/generate_ctm_leak_report.sh <<'EOF'
#!/bin/bash
REPORT_FILE="/var/log/ctm_mem_leak_report_$(date +%Y%m%d).txt"

echo "Control-M Memory Leak Analysis Report" > $REPORT_FILE
echo "Generated: $(date)" >> $REPORT_FILE
echo "=====================================" >> $REPORT_FILE

# 1. Process memory growth
echo -e "\nMemory Growth Over Time:" >> $REPORT_FILE
awk -F, '{print $1,$3,$4}' /var/log/ctm_mem_*.log | sort | uniq -c >> $REPORT_FILE

# 2. Suspicious allocations
echo -e "\nTop 20 Memory Allocation Patterns:" >> $REPORT_FILE
grep "allocated" /var/log/ctm_allocations.log | awk '{print $5}' | sort | uniq -c | sort -nr | head -20 >> $REPORT_FILE

# 3. Heap analysis
echo -e "\nHeap Memory Summary:" >> $REPORT_FILE
xmlstarlet sel -t -v "//allocated" /tmp/ctm_heap.xml | sort -n | tail -20 >> $REPORT_FILE

# 4. Leak candidates
echo -e "\nPotential Leaks (unfreed allocations):" >> $REPORT_FILE
grep -B1 "allocated" /var/log/ctm_allocations.log | grep -A1 -B1 "freed" | grep -v "freed" >> $REPORT_FILE

echo "Report generated: $REPORT_FILE"
EOF

sudo chmod +x /usr/local/bin/generate_ctm_leak_report.sh
sudo /usr/local/bin/generate_ctm_leak_report.sh
```

## 5. Important Notes

1. **Production Impact**: Valgrind and SystemTap may add 10-20% overhead
2. **Duration**: Run monitoring for at least 24 hours to capture patterns
3. **Data Collection**: Include these files when contacting BMC Support:
   ```bash
   tar -czvf ctm_mem_debug.tar.gz \
     /var/log/ctm_mem_*.log \
     /var/log/ctm_allocations.log \
     /tmp/ctm_heap.xml \
     /var/log/ctm_valgrind.log \
     /var/log/ctm_mem_leak_report_*.txt
   ```

Would you like me to provide specific commands to:
1. Correlate memory spikes with Tanium scan activity?
2. Set up alerts when Control-M memory exceeds thresholds?
3. Extract Java heap details (if Control-M uses Java components)?

# SystemTap Script for Tracing Tanium-Control-M Interactions

Here's a comprehensive SystemTap script to monitor interactions between Tanium and Control-M processes on OEL 9:

## Script: `tanium_ctm_interaction.stp`
```stp
#!/usr/bin/stap

global tanium_pids, ctm_pids, interactions

probe begin {
    printf("Starting Tanium-Control-M Interaction Tracer\n")
    printf("Monitoring period: %d seconds\n", $1)
    printf("===========================================\n")
}

/* Track process creation */
probe process("/opt/Tanium/TaniumClient/taniumclient").function("exec*") {
    tanium_pids[pid()] = 1
}

probe process("/opt/ControlM/*bin/*").function("exec*") {
    ctm_pids[pid()] = 1
}

/* Monitor file access between processes */
probe syscall.open, syscall.openat {
    if (pid() in tanium_pids) {
        if (isinstr(user_string($filename), "/opt/ControlM") || 
            isinstr(user_string($filename), "ctm")) {
            interactions[pid(), tid()] <<< sprintf("Tanium[%d] accessed %s", pid(), user_string($filename))
        }
    }
    if (pid() in ctm_pids) {
        if (isinstr(user_string($filename), "/opt/Tanium") {
            interactions[pid(), tid()] <<< sprintf("ControlM[%d] accessed %s", pid(), user_string($filename))
        }
    }
}

/* Monitor process communication */
probe syscall.ptrace, syscall.process_vm_readv, syscall.process_vm_writev {
    if (pid() in tanium_pids && $2 in ctm_pids) {
        interactions[pid(), tid()] <<< sprintf("Tanium[%d] inspected ControlM[%d] via %s", pid(), $2, pn())
    }
    if (pid() in ctm_pids && $2 in tanium_pids) {
        interactions[pid(), tid()] <<< sprintf("ControlM[%d] inspected Tanium[%d] via %s", pid(), $2, pn())
    }
}

/* Monitor shared memory */
probe syscall.shmget, syscall.shmat {
    if (pid() in tanium_pids || pid() in ctm_pids) {
        interactions[pid(), tid()] <<< sprintf("Process[%d] used shared memory via %s", pid(), pn())
    }
}

/* Periodic reporting */
probe timer.sec($1) {
    printf("\n=== Interaction Report ===\n")
    foreach ([p,t] in interactions) {
        printf("Process %d (TID %d):\n", p, t)
        foreach (msg in interactions[p,t]) {
            printf("  %s\n", msg)
        }
    }
    printf("=========================\n")
    delete interactions
}

probe end {
    printf("\nTracing completed. Summary:\n")
    printf("Tanium PIDs tracked: %d\n", sizeof(tanium_pids))
    printf("Control-M PIDs tracked: %d\n", sizeof(ctm_pids))
}
```

## How to Use This Script

1. **Install Dependencies**:
   ```bash
   sudo dnf install systemtap kernel-devel-$(uname -r) kernel-debuginfo-$(uname -r)
   ```

2. **Run the Script** (monitor for 300 seconds = 5 minutes):
   ```bash
   sudo stap -v tanium_ctm_interaction.stp 300 -o /var/log/tanium_ctm_interactions.log
   ```

3. **Alternative - Run as Background Service**:
   ```bash
   sudo nohup stap -v tanium_ctm_interaction.stp 600 -o /var/log/tanium_ctm_interactions_$(date +%Y%m%d).log &
   ```

## Key Features

1. **Tracks**:
   - File access between processes
   - Process inspection (ptrace, process_vm_* calls)
   - Shared memory usage
   - Library injections

2. **Output Includes**:
   - Timestamp of each interaction
   - Process IDs involved
   - Type of interaction
   - Target files or resources

3. **Customization Options**:
   - Adjust the monitoring period (change the `$1` parameter)
   - Add more syscalls to monitor (e.g., `ioctl`, `kill`)
   - Filter specific directories or file patterns

## Enhanced Version with Memory Tracking

For memory-specific interactions, use this modified probe:

```stp
/* Memory-specific interactions */
probe vfs.read, vfs.write {
    if (pid() in tanium_pids && isinstr(path, "/proc/") {
        target_pid = strtol(substr(path, strstr(path, "/proc/")+6, 10)
        if (target_pid in ctm_pids) {
            interactions[pid(), tid()] <<< sprintf("Tanium[%d] read ControlM[%d] memory via %s", 
                pid(), target_pid, path)
        }
    }
}
```

## Important Notes

1. **Performance Impact**: SystemTap adds ~5-15% overhead during tracing
2. **Security**: Requires root privileges to run
3. **Duration**: Run for at least 1-2 hours to capture meaningful patterns
4. **Analysis**: Look for:
   - Frequent file accesses to ControlM config/log files
   - Memory inspection operations
   - Unexpected ptrace calls

Would you like me to modify the script to:
1. Focus specifically on memory operations only?
2. Add timestamping to each interaction?
3. Include network communication tracing between the processes?

# Correlating Control-M Memory Spikes with Tanium Scan Activity

Here's a comprehensive approach to identify and correlate memory spikes in Control-M processes with Tanium's scanning activity:

## 1. Real-time Monitoring System

### Setup Combined Monitoring Script
```bash
sudo tee /usr/local/bin/monitor_tanium_ctm.sh <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/tanium_ctm_correlation_$(date +%Y%m%d).csv"
echo "Timestamp,CTM_PID,CTM_RSS(KB),CTM_%MEM,Tanium_CPU%,Tanium_Scan_Activity" > $LOG_FILE

# Get Control-M base PIDs
CTM_PIDS=$(pgrep -f "ctm_server")

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Capture Control-M memory usage
    CTM_STATS=$(ps -o pid,rss,%mem -p $CTM_PIDS | awk 'NR>1')
    
    # Capture Tanium CPU usage and active scans
    TANIUM_CPU=$(top -bn1 -p $(pgrep -f "taniumclient") | awk '/tanium/ {print $9}')
    TANIUM_SCANS=$(sudo lsof -p $(pgrep -f "taniumclient") | grep -c " REG ")
    
    # Log all data
    while IFS= read -r line; do
        echo "$TIMESTAMP,$line,$TANIUM_CPU,$TANIUM_SCANS" >> $LOG_FILE
    done <<< "$CTM_STATS"
    
    sleep 5
done
EOF

sudo chmod +x /usr/local/bin/monitor_tanium_ctm.sh
```

### Run as Service
```bash
sudo tee /etc/systemd/system/tanium_ctm_monitor.service <<EOF
[Unit]
Description=Tanium-CTM Memory Correlation Monitor

[Service]
ExecStart=/usr/local/bin/monitor_tanium_ctm.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start tanium_ctm_monitor
```

## 2. Tanium Scan Activity Detection

### Enhanced SystemTap Script for Scan Detection
```stp
#!/usr/bin/stap

global scan_activity

probe process("/opt/Tanium/TaniumClient/taniumclient").function("*scan*") {
    scan_activity[pid()] <<< gettimeofday_ms()
}

probe timer.sec(5) {
    printf("[%s] Tanium scan operations: %d\n", ctime(gettimeofday()), @sum(scan_activity[pid()]))
    delete scan_activity
}
```

### Run Scan Monitor
```bash
sudo stap -ve 'probe process("/opt/Tanium/TaniumClient/taniumclient").function("*scan*") { 
    printf("%d Tanium scan started at %s\n", pid(), ctime(gettimeofday())) 
}' -o /var/log/tanium_scans.log
```

## 3. Correlation Analysis

### Generate Correlation Report
```bash
sudo tee /usr/local/bin/generate_correlation_report.sh <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/tanium_ctm_correlation_*.csv"
REPORT_FILE="/var/log/tanium_ctm_correlation_report_$(date +%Y%m%d).html"

# Create HTML report
echo "<html><body><h1>Tanium-Control-M Correlation Report</h1>" > $REPORT_FILE
echo "<p>Generated: $(date)</p>" >> $REPORT_FILE

# Find memory spikes with Tanium activity
echo "<h2>Memory Spikes During Tanium Scans</h2>" >> $REPORT_FILE
awk -F, '$6 > 5 && $3 > 1000000 {print}' $LOG_FILE | \
sort -k3 -nr | \
awk -F, 'BEGIN{print "<table border=1><tr><th>Timestamp</th><th>CTM PID</th><th>RSS (KB)</th><th>Tanium CPU%</th><th>Open Files</th></tr>"}
{printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",$1,$2,$3,$5,$6}
END{print "</table>"}' >> $REPORT_FILE

# Generate time-series plot
echo "<h2>Memory/Scan Activity Timeline</h2>" >> $REPORT_FILE
echo "<pre>" >> $REPORT_FILE
awk -F, '{print $1,$3/1024,$5,$6}' $LOG_FILE | \
gnuplot -e "set terminal dumb; set title 'Memory vs Tanium Activity'; \
set xdata time; set timefmt '%Y-%m-%d %H:%M:%S'; \
plot '-' using 1:2 with lines title 'CTM Memory (MB)', \
'' using 1:3 with lines title 'Tanium CPU%', \
'' using 1:4 with lines title 'Open Files'" 2>&1 | \
tee -a $REPORT_FILE
echo "</pre></body></html>" >> $REPORT_FILE

echo "Report generated: $REPORT_FILE"
EOF

sudo chmod +x /usr/local/bin/generate_correlation_report.sh
```

## 4. Visualization

### Install Required Packages
```bash
sudo dnf install gnuplot python3-pandas -y
```

### Create Interactive Plot
```python
sudo tee /usr/local/bin/plot_correlation.py <<'EOF'
#!/usr/bin/python3
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime

# Read data
df = pd.read_csv('/var/log/tanium_ctm_correlation_*.csv', 
                 parse_dates=['Timestamp'],
                 date_parser=lambda x: datetime.strptime(x, '%Y-%m-%d %H:%M:%S'))

# Normalize data
df['CTM_Memory_MB'] = df['CTM_RSS(KB)'] / 1024
df['Scan_Intensity'] = df['Tanium_Scan_Activity'] / df['Tanium_Scan_Activity'].max()

# Create plot
plt.figure(figsize=(12,6))
plt.plot(df['Timestamp'], df['CTM_Memory_MB'], label='Control-M Memory (MB)')
plt.plot(df['Timestamp'], df['Tanium_CPU%'], label='Tanium CPU %')
plt.plot(df['Timestamp'], df['Scan_Intensity']*100, label='Scan Intensity (scaled)')
plt.xlabel('Time')
plt.ylabel('Usage')
plt.title('Control-M Memory vs Tanium Activity')
plt.legend()
plt.grid()
plt.savefig('/var/log/tanium_ctm_correlation.png')
print("Plot saved to /var/log/tanium_ctm_correlation.png")
EOF

sudo chmod +x /usr/local/bin/plot_correlation.py
```

## 5. Key Analysis Points

1. **Temporal Correlation**:
   ```bash
   # Find events where Tanium activity precedes memory spikes
   awk -F, '$5 > 30 && $3 > 1500000 {print}' /var/log/tanium_ctm_correlation_*.csv
   ```

2. **Scan Impact Score**:
   ```bash
   # Calculate correlation coefficient
   python3 -c "import pandas as pd; df = pd.read_csv('/var/log/tanium_ctm_correlation_*.csv'); 
   print(df[['CTM_RSS(KB)','Tanium_Scan_Activity']].corr())"
   ```

3. **Peak Analysis**:
   ```bash
   # Show top 10 memory spikes with Tanium context
   sort -t, -k3 -nr /var/log/tanium_ctm_correlation_*.csv | head -10 | \
   awk -F, '{printf "Time: %s\nCTM Memory: %.1fGB\nTanium CPU: %s%%\nOpen Files: %d\n\n", $1, $3/1048576, $5, $6}'
   ```

## Recommended Actions

1. **If Correlation Found**:
   ```bash
   # Add Control-M exclusions to Tanium config
   sudo tee -a /opt/Tanium/TaniumClient/config.ini <<CONFIG
   [Exclusions]
   Path=/opt/ControlM/
   Process=ctm.*
   Process=ag_.*
   CONFIG
   ```

2. **Schedule Tanium Scans**:
   ```bash
   # Configure Tanium to avoid Control-M peak hours
   sudo crontab -l | { cat; echo "0 1 * * * /opt/Tanium/TaniumClient/taniumclient -scan"; } | sudo crontab -
   ```

3. **Memory Protection**:
   ```bash
   # Limit Control-M memory usage via cgroups
   sudo mkdir /sys/fs/cgroup/memory/ctm
   echo $((16 * 1024 * 1024 * 1024)) > /sys/fs/cgroup/memory/ctm/memory.limit_in_bytes
   for pid in $(pgrep -f "ctm"); do echo $pid > /sys/fs/cgroup/memory/ctm/tasks; done
   ```

To view the correlation report:
```bash
sudo /usr/local/bin/generate_correlation_report.sh
sudo firefox /var/log/tanium_ctm_correlation_report_*.html
```

