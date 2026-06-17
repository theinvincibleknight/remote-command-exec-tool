#!/bin/bash
#=============================================================================
# Script: disk_usage.sh
# Description: Check disk usage and alert if any partition exceeds threshold
# Usage:  ./disk_usage.sh [threshold_percentage]
#=============================================================================

THRESHOLD="${1:-80}"

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "---"
echo "Disk Usage Report (Alert threshold: ${THRESHOLD}%)"
echo ""

# Show all mounted filesystems
echo "All Filesystems:"
df -h | grep -v "tmpfs\|udev" | head -1
df -h | grep -v "tmpfs\|udev" | tail -n +2 | sort -k5 -rn
echo ""

# Check for partitions exceeding threshold
ALERT=false
echo "Partitions exceeding ${THRESHOLD}% usage:"
while IFS= read -r line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    if [[ "$usage" -ge "$THRESHOLD" ]]; then
        echo "  [ALERT] $line"
        ALERT=true
    fi
done <<< "$(df -h | grep -v "tmpfs\|udev\|Filesystem")"

if ! $ALERT; then
    echo "  None - all partitions within limits."
fi

echo ""

# Show top 10 largest directories in /
echo "Top 10 largest directories in /:"
sudo du -sh /* 2>/dev/null | sort -rh | head -10
