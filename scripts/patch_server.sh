#!/bin/bash
#=============================================================================
# Script: patch_server.sh
# Description: Update and upgrade the server (security patches & package updates)
# Usage:  ./patch_server.sh [--security-only] [--reboot]
#=============================================================================

SECURITY_ONLY=false
REBOOT_AFTER=false

for arg in "$@"; do
    case $arg in
        --security-only) SECURITY_ONLY=true ;;
        --reboot)        REBOOT_AFTER=true ;;
    esac
done

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Uptime: $(uptime -p)"
echo "---"
echo "Patching started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check current kernel
echo "Current Kernel: $(uname -r)"
echo ""

# Update package list
echo "[$(date '+%H:%M:%S')] Updating package list..."
sudo apt-get update -qq 2>&1
echo ""

# Show upgradable packages
echo "[$(date '+%H:%M:%S')] Upgradable packages:"
apt list --upgradable 2>/dev/null | grep -v "^Listing"
echo ""

if $SECURITY_ONLY; then
    # Security updates only
    echo "[$(date '+%H:%M:%S')] Installing security updates only..."
    sudo apt-get upgrade -y --only-upgrade $(apt list --upgradable 2>/dev/null | grep -i security | cut -d'/' -f1) 2>&1
else
    # Full upgrade
    echo "[$(date '+%H:%M:%S')] Performing full system upgrade..."
    sudo apt-get upgrade -y 2>&1
    echo ""
    echo "[$(date '+%H:%M:%S')] Running dist-upgrade..."
    sudo apt-get dist-upgrade -y 2>&1
fi

echo ""

# Cleanup
echo "[$(date '+%H:%M:%S')] Cleaning up..."
sudo apt-get autoremove -y 2>&1
sudo apt-get autoclean 2>&1
echo ""

# Check if reboot is needed
if [[ -f /var/run/reboot-required ]]; then
    echo "[WARNING] REBOOT REQUIRED"
    cat /var/run/reboot-required.pkgs 2>/dev/null
    if $REBOOT_AFTER; then
        echo "[$(date '+%H:%M:%S')] Rebooting server in 1 minute..."
        sudo shutdown -r +1 "System reboot after patching"
    fi
else
    echo "[INFO] No reboot required."
fi

echo ""
echo "Patching completed at: $(date '+%Y-%m-%d %H:%M:%S')"
