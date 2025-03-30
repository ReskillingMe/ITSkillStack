#!/bin/bash
# Kernel Parameter Optimizer
CONFIG_FILE="/etc/sysctl.d/99-controlm.conf"

# 1. Backup current settings
sudo sysctl -a > "/tmp/kernel_params_backup_$(date +%Y%m%d).conf"

# 2. Apply Control-M friendly values
echo "vm.dirty_ratio = 20" | sudo tee "$CONFIG_FILE"
echo "kernel.shmall = 4194304" | sudo tee -a "$CONFIG_FILE"
echo "kernel.yama.ptrace_scope = 1" | sudo tee -a "$CONFIG_FILE"

# 3. Reload
sudo sysctl -p "$CONFIG_FILE"

echo "Kernel parameters updated. Reboot recommended for LSM changes."


