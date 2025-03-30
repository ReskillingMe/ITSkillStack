# Control-M High Memory Consumption Troubleshooting Guide

## Table of Contents
1. [Initial Symptoms](#initial-symptoms)
2. [CrowdStrike Impact Analysis](#crowdstrike-impact-analysis)
3. [Kernel Panic Behavior](#kernel-panic-behavior)
4. [Tanium Impact Analysis](#tanium-impact-analysis)
5. [Troubleshooting Script](#troubleshooting-script)
6. [Validation Steps](#validation-steps)

---

## Initial Symptoms
### Problem Statement
Control-M agent process exhibits continuously increasing memory consumption, even after reboots and CrowdStrike agent removal.

### Key Observations
- Memory growth persists across nodes (with/without CrowdStrike)
- No immediate correlation with job execution peaks
- Possible kernel-level interactions

---

## CrowdStrike Impact Analysis
### How CrowdStrike Affects Control-M
| Mechanism | Impact | Detection Command |
|-----------|--------|-------------------|
| **Real-time scanning** | Increases I/O wait and memory buffers | `sudo ausearch -k crowdstrike_file_scan \| grep "/opt/controlm"` |
| **Kernel hook conflicts** | Memory leaks from competing LSM modules | `lsmod \| grep -E "falcon\|controlm"` |
| **Post-reboot scans** | Aggressive baseline scans stall Control-M | `grep -i "scan" /var/log/crowdstrike/falconhose.log` |

### Critical Parameters Modified by CrowdStrike

	```bash
	# Check modified parameters
	sudo grep -r "" /etc/sysctl.d/*falcon*

	# Compare with defaults
	diff -u <(sort /usr/lib/sysctl.d/50-default.conf) <(sudo sysctl -a | sort)


## ctl_mem_troubleshoot.sh

Here’s a comprehensive shell script for troubleshooting high memory consumption in Control-M (or any process) on Linux, with CrowdStrike/Tanium-specific checks:


Key Features of the Script

Process Memory Tracking

Monitors RSS/VSZ trends over time.

Identifies memory-mapped files with pmap.

Security Tool Audits

Checks CrowdStrike/Tanium status and exclusions.

Kernel Diagnostics

Reviews OOM events, slab memory, and kernel modules.

Control-M Specific Checks

Validates agent_parm.txt settings and job output bloat.

Java Heap Dumps

Captures heap dumps if Control-M uses Java.

Organized Output

Saves all data to timestamped /tmp directory.

Usage

	```bash
	# Make executable
	chmod +x ctl_mem_troubleshoot.sh

	# Run against Control-M PID
	sudo ./ctl_mem_troubleshoot.sh $(pgrep ctmag)

	# For Java-based agents, analyze heap dump with:
	jhat /tmp/ctl_mem_diagnostics_*/ctl_mem_heap.hprof


Expected Output
1_system_overview.txt → Host/kernel info

2_process_memory.txt → Memory usage trends

3_security_tools.txt → CrowdStrike/Tanium configs

4_kernel_diagnostics.txt → OOM/slab info

5_controlm_config.txt → Control-M settings

For recurring issues, share the /tmp/ctl_mem_diagnostics_* folder with BMC Support.


## Mer



## List of scripts

Set of global shell scripts to troubleshoot complex Control-M memory issues, covering system-wide checks, security tool audits, and kernel diagnostics. These scripts are designed for Oracle Linux 9 but adaptable to other distributions.

1. System-Wide Memory Analyzer (system_mem_profile.sh)
Purpose: Identify memory hogs system-wide, including Control-M and security tools.

2. Security Tool Conflict Detector (security_tool_audit.sh)
Purpose: Audit CrowdStrike/Tanium configurations impacting Control-M.

3. Control-M Agent Deep Inspector (ctl_mem_deepdive.sh)
Purpose: Focused analysis of Control-M’s memory usage and leaks.

4. Kernel Parameter Tuner (kernel_param_tuner.sh)
Purpose: Adjust kernel parameters to mitigate memory issues.

5. Automated Validation Suite (ctl_mem_validate.sh)
Purpose: Post-fix validation to ensure stability.

Usage Guide
Run all scripts sequentially:

bash
Copy
sudo ./system_mem_profile.sh
sudo ./security_tool_audit.sh
sudo ./ctl_mem_deepdive.sh
sudo ./kernel_param_tuner.sh
sudo ./ctl_mem_validate.sh
Review outputs in /tmp/ directories.

Escalate findings:

Share system_mem_profile.log with sysadmins.

Provide security_audit/ data to CrowdStrike/Tanium teams.

Send ctl_mem_deepdive/ to BMC Support.

Key Features
Script	What It Does	Critical Outputs
system_mem_profile.sh	System-wide memory trends	oom_events.log, slab_mem.log
security_tool_audit.sh	Audits security tools	crowdstrike_exclusions.txt
ctl_mem_deepdive.sh	Control-M specific leaks	heap.hprof (Java), pmap.txt
kernel_param_tuner.sh	Optimizes kernel for Control-M	Backup in /tmp/
ctl_mem_validate.sh	Post-fix stability checks	1-hour memory trend log
Example Workflow
mermaid

Copy
graph TD
    A[High Memory Alert] --> B[Run system_mem_profile.sh]
    B --> C{Is Control-M the top consumer?}
    C -->|Yes| D[Run ctl_mem_deepdive.sh]
    C -->|No| E[Check security_tool_audit.sh]
    D --> F[Analyze heap.hprof/pmap.txt]
    E --> G[Adjust exclusions in CrowdStrike/Tanium]
    F & G --> H[Apply kernel_param_tuner.sh]
    H --> I[Validate with ctl_mem_validate.sh]


Notes

Prerequisites:

jmap for Java heap dumps (install JDK if missing).

slabtop for kernel slab analysis (yum install procps-ng).

Safety: All scripts backup data before making changes.

Automation: Schedule ctl_mem_validate.sh for periodic checks.

These scripts provide a comprehensive toolkit to diagnose and resolve complex Control-M memory issues in environments with security tools like CrowdStrike/Tanium.


## Set of advanced scripts to track Control-M processes and subprocesses by memory usage groups, generating analysis-ready reports:


1. Control-M Process Hierarchy Tracker (ctl_process_hierarchy.sh)
Tracks parent-child relationships and memory usage in a tree format.


2. Memory Trend Analyzer (ctl_mem_trend.sh)
Captures memory usage trends over time with group classification.

3. Subprocess Memory Profiler (ctl_subprocess_profiler.sh)
Deep-dives into Control-M subprocesses using pmap and strace.

4. Report Generator (ctl_mem_report_gen.sh)
Transforms raw data into HTML reports for analysis.

Usage Workflow

Start monitoring:

	./ctl_process_hierarchy.sh && ./ctl_mem_trend.sh

Profile subprocesses (after detecting anomalies):

	./ctl_subprocess_profiler.sh

Generate reports:

	./ctl_mem_report_gen.sh /tmp/ctl_mem_hierarchy_20240315_1420

Key Features
Script	Purpose	Outputs
ctl_process_hierarchy.sh	Maps process tree with memory groups	process_tree.txt, mem_groups.txt
ctl_mem_trend.sh	Tracks memory usage over time	mem_trend.csv, mem_group_summary.txt
ctl_subprocess_profiler.sh	Deep-dives into child processes	pmap_*.txt, strace_*.txt
ctl_mem_report_gen.sh	Creates HTML reports	analysis_report.html

Sample Analysis Workflow

graph TD
    A[Start ctl_mem_trend.sh] --> B{Memory spike?}
    B -->|Yes| C[Run ctl_process_hierarchy.sh]
    B -->|No| D[Continue monitoring]
    C --> E[Identify problematic group]
    E --> F[Run ctl_subprocess_profiler.sh on target PIDs]
    F --> G[Generate HTML report]


Notes

Requirements:

	pstree (install via yum install psmisc)

	pmap (part of procps-ng package)

Customization:

Adjust memory group thresholds in scripts as needed.

Extend monitoring duration in ctl_mem_trend.sh.

Automation:

Schedule ctl_mem_trend.sh via cron for continuous monitoring:

	*/15 * * * * /path/to/ctl_mem_trend.sh

These scripts provide enterprise-grade tracking of Control-M memory usage with actionable insights for troubleshooting.
