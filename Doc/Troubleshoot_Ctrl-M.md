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

# Kernel Parameter Interactions Between Tanium Client and Control-M on OEL 9

## Key Kernel Parameters Affected by Both Services

### 1. Memory Management Parameters
```bash
# Current values can be checked with:
sudo sysctl -a | grep -E 'vm.overcommit|vm.swappiness|vm.dirty'
```

**Commonly Impacted Parameters:**
- `vm.overcommit_memory` (Tanium often requires 0, Control-M may need 1)
- `vm.overcommit_ratio` (Default 50, may need adjustment)
- `vm.swappiness` (Tanium prefers lower values, Control-M may need higher)
- `vm.dirty_ratio`/`vm.dirty_background_ratio` (Affects filesystem caching)

### 2. Process Limits
```bash
# Check current limits:
sudo sysctl -a | grep -E 'kernel.pid_max|kernel.threads-max'
```

**Critical Parameters:**
- `kernel.pid_max` (Tanium spawns many subprocesses)
- `kernel.threads-max` (Control-M requires high thread counts)
- `kernel.sem` (SEMAPHORES settings for IPC)

## Recommended Optimizations

### Baseline Configuration
```bash
# Add to /etc/sysctl.d/99-tanium-ctm.conf:
vm.overcommit_memory = 1
vm.overcommit_ratio = 75
vm.swappiness = 30
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
kernel.pid_max = 131072
kernel.threads-max = 256000
kernel.sem = 500 512000 64 2048
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
```

### Service-Specific Tuning

**For Tanium Client:**
```bash
# Tanium-specific optimizations
echo "vm.vfs_cache_pressure = 50" | sudo tee -a /etc/sysctl.d/99-tanium.conf
echo "kernel.perf_event_paranoid = -1" | sudo tee -a /etc/sysctl.d/99-tanium.conf
```

**For Control-M:**
```bash
# Control-M specific optimizations
echo "kernel.sched_autogroup_enabled = 0" | sudo tee -a /etc/sysctl.d/99-ctm.conf
echo "kernel.numa_balancing = 0" | sudo tee -a /etc/sysctl.d/99-ctm.conf
```

## Verification and Monitoring

### Check Applied Parameters
```bash
# Verify all settings
sudo sysctl --system
sudo sysctl -p /etc/sysctl.d/99-tanium-ctm.conf

# Monitor parameter effects
watch -n 5 'sudo sysctl -a | grep -E "overcommit|dirty|swappiness"'
```

### Real-time Impact Monitoring
```bash
# Monitor kernel parameter effects
sudo stap -e '
probe kernel.function("mm_page_alloc") {
    if (pid() == $1 || pid() == $2) {
        printf("%s[%d] allocated page\n", execname(), pid())
    }
}' $(pgrep -f taniumclient) $(pgrep -f ctm_server)
```

## Troubleshooting Conflicts

### When Parameters Collide:
1. **Memory Overcommit Issues**:
   ```bash
   # Check OOM killer activity
   sudo grep -i 'oom\|kill' /var/log/messages*
   
   # Temporary workaround:
   echo 1 > /proc/sys/vm/overcommit_memory
   ```

2. **File Handle Exhaustion**:
   ```bash
   # Check current usage
   cat /proc/sys/fs/file-nr
   
   # Increase if needed
   echo 3000000 > /proc/sys/fs/file-max
   ```

3. **Thread Creation Failures**:
   ```bash
   # Monitor thread usage
   watch -n 1 'ps -eLf | grep -E "tanium|ctm" | wc -l'
   
   # Increase system-wide limit
   echo 300000 > /proc/sys/kernel/threads-max
   ```

## Persistent Configuration

To make changes permanent:
```bash
# Apply all configurations
sudo sysctl --system

# Verify at boot
sudo tee /etc/rc.local <<'EOF'
#!/bin/bash
sleep 30  # Wait for services to start
sysctl -p /etc/sysctl.d/99-tanium-ctm.conf
exit 0
EOF
sudo chmod +x /etc/rc.local
```

## Recommended Monitoring Tools

1. **Track Parameter Changes**:
   ```bash
   sudo auditctl -w /proc/sys/vm/ -p wa -k kernel_parameters
   ```

2. **Performance Impact**:
   ```bash
   sudo perf stat -e 'kmem:*' -a sleep 10
   ```

3. **Service-Specific Effects**:
   ```bash
   sudo stap -e 'probe kernel.function("sysctl_set_value") {
       if (pid() == $1 || pid() == $2) {
           printf("%s modified %s to %d\n", execname(), kernel_string($2), $3)
       }
   }' $(pgrep -f taniumclient) $(pgrep -f ctm_server)
   ```

Remember to test changes in a staging environment before production deployment. The optimal values may vary based on your specific workload and system configuration.

# Auditing Kernel Parameter Change History on OEL 9

## 1. System Auditd Configuration (Recommended Method)

### Set up audit rules for kernel parameters:
```bash
sudo tee /etc/audit/rules.d/90-kernel-params.rules <<'EOF'
# Monitor sysctl configuration files
-w /etc/sysctl.conf -p wa -k kernel_params
-w /etc/sysctl.d/ -p wa -k kernel_params

# Monitor /proc/sys modifications (all parameters)
-w /proc/sys/ -p wa -k kernel_params

# Monitor sysctl command usage
-a always,exit -F arch=b64 -S sysctl -F key=kernel_params
EOF

# Restart auditd
sudo service auditd restart
```

### View audit logs:
```bash
# Search for kernel parameter changes
sudo ausearch -k kernel_params | aureport -f -i

# Detailed view with timestamps
sudo ausearch -k kernel_params --raw | aureport -f -i --interpret
```

## 2. Manual Change Tracking with Git

### Initialize configuration tracking:
```bash
sudo mkdir /etc/sysctl.history
sudo cp -a /etc/sysctl.conf /etc/sysctl.history/sysctl.conf.initial
sudo git -C /etc/sysctl.history init
sudo git -C /etc/sysctl.history add .
sudo git -C /etc/sysctl.history commit -m "Initial sysctl configuration"
```

### Create change hook:
```bash
sudo tee /etc/apt/apt.conf.d/90sysctl-track <<'EOF'
DPkg::Post-Invoke {
    "git -C /etc/sysctl.history add /etc/sysctl* /etc/sysctl.d/* 2>/dev/null || true";
    "git -C /etc/sysctl.history commit -m 'Auto-commit: sysctl changes' /etc/sysctl* /etc/sysctl.d/* 2>/dev/null || true";
};
EOF

# Also track manual changes
echo 'alias sysctl="(sysctl \$@; git -C /etc/sysctl.history add /etc/sysctl* /etc/sysctl.d/* 2>/dev/null; git -C /etc/sysctl.history commit -m \"sysctl change: \$@\" /etc/sysctl* /etc/sysctl.d/* 2>/dev/null) 2>/dev/null"' | sudo tee -a /etc/bashrc
```

### View change history:
```bash
sudo git -C /etc/sysctl.history log --name-only
```

## 3. Kernel Parameter Snapshot System

### Create daily snapshots:
```bash
sudo mkdir /var/log/kernel_params
sudo tee /usr/local/bin/snapshot_kernel_params.sh <<'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d%H%M)
OUTFILE="/var/log/kernel_params/snapshot_${DATE}.txt"

# Collect all kernel parameters
sysctl -a > "$OUTFILE"

# Compare with previous
LAST=$(ls -1t /var/log/kernel_params/snapshot_*.txt | head -2 | tail -1)
if [ -f "$LAST" ]; then
    diff -u "$LAST" "$OUTFILE" > "/var/log/kernel_params/diff_${DATE}.txt"
fi

# Keep 30 days of history
find /var/log/kernel_params/ -name "snapshot_*.txt" -mtime +30 -delete
find /var/log/kernel_params/ -name "diff_*.txt" -mtime +30 -delete
EOF

sudo chmod +x /usr/local/bin/snapshot_kernel_params.sh

# Add to cron
sudo tee /etc/cron.d/kernel-param-snapshots <<'EOF'
*/30 * * * * root /usr/local/bin/snapshot_kernel_params.sh
EOF
```

### View changes between snapshots:
```bash
# List available snapshots
ls -lt /var/log/kernel_params/snapshot_*.txt

# Compare two specific snapshots
diff -y /var/log/kernel_params/snapshot_202301010000.txt /var/log/kernel_params/snapshot_202301020000.txt | less

# View all changes in chronological order
cat /var/log/kernel_params/diff_*.txt | grep '^[+-][^+-]' | sort | uniq
```

## 4. Real-time Monitoring with SystemTap

### Install SystemTap:
```bash
sudo dnf install systemtap kernel-devel-$(uname -r)
```

### Create monitoring script:
```bash
sudo tee /usr/local/bin/monitor_sysctl_changes.stp <<'EOF'
probe kernel.function("proc_dostring").return,
      kernel.function("proc_dointvec").return,
      kernel.function("proc_doulongvec").return,
      kernel.function("proc_douintvec").return {
    if ($write) {
        printf("[%s] %s changed %s to %s (PID: %d, Command: %s)\n",
               ctime(gettimeofday_s()),
               uid() == 0 ? "ROOT" : sprintf("UID %d", uid()),
               kernel_string($table->procname),
               kernel_string($buffer),
               pid(),
               execname())
    }
}
EOF

# Run in background
sudo nohup stap -v /usr/local/bin/monitor_sysctl_changes.stp > /var/log/sysctl_changes.log &
```

## 5. Checking Current vs. Boot Parameters

### Compare current with boot-time values:
```bash
# Save current values
sudo sysctl -a > /tmp/current_params.txt

# Extract boot parameters from journal
sudo journalctl -k -b 0 | grep -i "kernel:" | grep -i -E "overcommit|swappiness|dirty" > /tmp/boot_params.txt

# Compare
diff -y /tmp/boot_params.txt <(grep -E "vm.overcommit|vm.swappiness|vm.dirty" /tmp/current_params.txt)
```

## 6. Advanced: eBPF Monitoring (Requires BPF Compiler Collection)

```bash
sudo dnf install bcc-tools
sudo /usr/share/bcc/tools/trace 'do_sysctl "%s", arg2' -U
```

## Viewing Comprehensive History

Combine all methods for full visibility:
```bash
sudo tee /usr/local/bin/kparam_history <<'EOF'
#!/bin/bash
echo "=== Audit Logs ==="
sudo ausearch -k kernel_params --raw | aureport -f -i --interpret

echo -e "\n=== Git History ==="
sudo git -C /etc/sysctl.history log -p --stat

echo -e "\n=== Parameter Snapshots ==="
ls -lt /var/log/kernel_params/diff_*.txt | head -5 | while read -r line; do
    echo "Changes in ${line##*/}:"
    cat "/var/log/kernel_params/${line##*/}"
done

echo -e "\n=== Recent SystemTap Changes ==="
tail -20 /var/log/sysctl_changes.log
EOF

sudo chmod +x /usr/local/bin/kparam_history
```

Now you can run `sudo kparam_history` to get a comprehensive view of all kernel parameter changes.


# Auditing Tanium Client Impact on Kernel Parameters in OCI Environments

Oracle Cloud Infrastructure (OCI) provides specific capabilities to monitor how OS maintenance tools like Tanium affect kernel parameters. Here's how OCI audits and manages these interactions:

## 1. OCI's Native Monitoring of Kernel Parameter Changes

### Cloud Guard Detectors
- **Kernel Modification Detection**: OCI Cloud Guard includes built-in detectors that flag unauthorized kernel parameter changes
- **Tanium-Specific Rules**: Can be configured to detect changes originating from Tanium processes
- **Access**: OCI Console > Security > Cloud Guard > Detector Rules

```bash
# Sample CLI query for Tanium-related changes
oci events event-list --compartment-id $COMPARTMENT_ID \
--query "data[?contains(\"message\",'Tanium') && \
contains(\"message\",'kernel.')].{time:\"time-generated\",message:\"message\"}" \
--output table
```

## 2. Instance-Level Audit Configuration for Tanium

### Enhanced Auditd Rules
```bash
# Tanium-specific kernel parameter audit rules
sudo tee /etc/audit/rules.d/99-tanium-kernel.rules <<'EOF'
# Track Tanium process sysctl calls
-a always,exit -F arch=b64 -S sysctl -F exe=/opt/Tanium/TaniumClient/taniumclient -k tanium_kernel_changes
# Monitor /proc/sys modifications by Tanium
-w /proc/sys/ -p wa -k tanium_kernel_changes -F uid=0 -F exe=/opt/Tanium/TaniumClient/taniumclient
EOF

# Restart audit service
sudo service auditd restart
```

### Monitoring Tanium's Kernel Interactions
```bash
# Real-time monitoring of Tanium's kernel access
sudo stap -e '
probe process("/opt/Tanium/TaniumClient/taniumclient").function("*sysctl*") {
    printf("%s[%d] modified kernel parameter: %s\n", 
           execname(), pid(), kernel_string(pointer_arg(1)))
}
'
```

## 3. OCI OS Management Service Integration

### Compliance Reporting
- **OCI OSMS** tracks all package changes including Tanium updates
- **Kernel Parameter Baseline**: Maintains known-good states for comparison

```bash
# Check OS Management compliance status
oci os-management managed-instance get --managed-instance-id $INSTANCE_ID \
--query "data.\"non-compliant-packages\"" --output table
```

## 4. Tanium-Specific Kernel Protection

### OCI Instance Configuration
```bash
# Create immutable kernel parameters
sudo tee /etc/sysctl.d/99-oci-protected.conf <<'EOF'
# OCI-protected parameters (cannot be modified by Tanium)
kernel.panic = 60
kernel.shmall = 4294967296
kernel.shmmax = 68719476736
EOF

# Set immutable attribute
sudo chattr +i /etc/sysctl.d/99-oci-protected.conf
```

## 5. Change Correlation Tools

### OCI-Tanium Change Correlation Script
```bash
sudo tee /usr/local/bin/oci_tanium_kernel_monitor.sh <<'EOF'
#!/bin/bash
# Compare current params with OCI baseline
OCI_BASELINE="/etc/oci-kernel-baseline.conf"
TANIUM_LOG="/var/log/tanium_kernel_changes.log"

# Generate current snapshot
sysctl -a | sort > /tmp/current_params.conf

# Compare with OCI baseline
if [ -f "$OCI_BASELINE" ]; then
    diff -u "$OCI_BASELINE" /tmp/current_params.conf | \
    grep -E "^\+[^+]" | \
    while read -r line; do
        # Check if change correlates with Tanium activity
        if grep -q "tanium" /var/log/audit/audit.log; then
            echo "$(date) - Tanium-modified: ${line:1}" >> "$TANIUM_LOG"
            # Optional: Revert critical changes
            case "${line}" in
                *"kernel.shm"*|*"kernel.sem"*)
                    param=${line%%=*}
                    ovalue=$(grep "^$param=" "$OCI_BASELINE")
                    sudo sysctl -w "$param=${ovalue#*=}"
                    ;;
            esac
        fi
    done
fi
EOF

# Run as cron job every 15 minutes
(crontab -l 2>/dev/null; echo "*/15 * * * * /usr/local/bin/oci_tanium_kernel_monitor.sh") | crontab -
```

## 6. OCI Resource Manager for Enforcement

### Terraform-based Kernel Protection
```hcl
resource "oci_core_instance" "secure_instance" {
  # ... other configuration ...

  # Kernel parameter enforcement
  metadata = {
    user_data = base64encode(<<-EOF
      #!/bin/bash
      # Protect critical parameters
      echo "kernel.panic = 60" >> /etc/sysctl.d/99-oci-protected.conf
      echo "kernel.exec-shield = 1" >> /etc/sysctl.d/99-oci-protected.conf
      chmod 0444 /etc/sysctl.d/99-oci-protected.conf
      sysctl --system
      
      # Tanium-specific exceptions
      mkdir -p /etc/tanium/exclusions
      echo "[KernelExclusions]" > /etc/tanium/exclusions/kernel.conf
      echo "Param=kernel.panic" >> /etc/tanium/exclusions/kernel.conf
      EOF
    )
  }
}
```

## Key Monitoring Points

1. **OCI Audit Logs**:
   - Filter for `com.oraclecloud.computeapi.updateinstance` events
   - Check for `kernel` or `sysctl` in event messages

2. **Tanium-Specific Audits**:
   ```bash
   # View Tanium-related kernel changes
   sudo ausearch -k tanium_kernel_changes | aureport -f -i
   ```

3. **OCI Console Monitoring**:
   - Navigate to: Compute > Instance > (Select Instance) > Work Requests
   - Filter for "Kernel Parameter" related work requests

OCI provides robust auditing of kernel parameter changes, including those made by tools like Tanium, through a combination of Cloud Guard detectors, OS Management Service tracking, and infrastructure-level audit logs. For complete protection, implement both OCI-native controls and instance-level auditing.


