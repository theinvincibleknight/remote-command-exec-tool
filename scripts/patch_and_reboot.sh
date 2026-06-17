#!/bin/bash
#=============================================================================
# Script: patch_and_reboot.sh
# Description: Patch server (hold critical packages), then reboot
# Held packages: mongo, mysql, java, python, docker
#=============================================================================

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Kernel: $(uname -r)"
echo "Uptime (before patch): $(uptime -p)"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Step 1: Update package list
echo "[$(date '+%H:%M:%S')] Running apt update..."
sudo apt update -y 2>&1 | tail -3
echo ""

# Step 2: Hold critical packages
HOLD_PKGS=$(dpkg --get-selections | grep -E 'mongo|mysql|java|python|docker' | awk '{print $1}')
if [[ -n "$HOLD_PKGS" ]]; then
    echo "[$(date '+%H:%M:%S')] Holding packages:"
    echo "$HOLD_PKGS" | while read pkg; do echo "  - $pkg"; done
    sudo apt-mark hold $HOLD_PKGS 2>&1
else
    echo "[$(date '+%H:%M:%S')] No matching packages to hold."
fi
echo ""

# Step 3: Upgrade
echo "[$(date '+%H:%M:%S')] Running apt-get upgrade..."
if sudo apt-get upgrade -y 2>&1 | tail -5; then
    echo ""
    echo "[$(date '+%H:%M:%S')] PATCH STATUS: SUCCESS"
else
    echo ""
    echo "[$(date '+%H:%M:%S')] PATCH STATUS: FAILED (exit code: $?)"
    echo "Skipping reboot due to patch failure."
    exit 1
fi
echo ""

# Step 4: Cleanup and Reboot
echo "[$(date '+%H:%M:%S')] Cleaning up and rebooting server..."
rm -f "$0" 2>/dev/null
sudo reboot
