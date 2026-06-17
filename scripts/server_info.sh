#!/bin/bash
#=============================================================================
# Script: server_info.sh
# Description: Collect basic server information (hostname, IP, uptime, OS)
#=============================================================================

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Uptime: $(uptime | awk '{print $3, $4}' | sed 's/,//')"
echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "Kernel: $(uname -r)"
echo "CPU Cores: $(nproc)"
echo "Memory Total: $(free -h | awk '/^Mem:/{print $2}')"
echo "Memory Used: $(free -h | awk '/^Mem:/{print $3}')"
echo "Disk Usage (/):"
df -h / | tail -1 | awk '{printf "  Total: %s, Used: %s, Available: %s, Use%%: %s\n", $2, $3, $4, $5}'
