#!/bin/bash
#=============================================================================
# Script: service_status.sh
# Description: Check the status of specified services on the remote server
# Usage:  ./service_status.sh "service1 service2 service3"
#         If no services specified, checks common services
#=============================================================================

SERVICES="$1"

# Default services to check if none specified
if [[ -z "$SERVICES" ]]; then
    SERVICES="ssh nginx apache2 mysql mongod docker redis-server cron"
fi

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "---"
echo "Service Status Report"
echo ""

printf "%-25s %-12s %-10s\n" "SERVICE" "STATUS" "ENABLED"
printf "%-25s %-12s %-10s\n" "-------" "------" "-------"

for svc in $SERVICES; do
    # Check if service exists
    if systemctl list-unit-files | grep -q "^${svc}"; then
        status=$(systemctl is-active "$svc" 2>/dev/null)
        enabled=$(systemctl is-enabled "$svc" 2>/dev/null)
        printf "%-25s %-12s %-10s\n" "$svc" "$status" "$enabled"
    fi
done

echo ""
echo "System Load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo "Running Processes: $(ps aux | wc -l)"
