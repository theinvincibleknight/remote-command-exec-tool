#!/bin/bash
#=============================================================================
# Script: check_uptime.sh
# Description: Check if server is up - fetch hostname, IP, kernel, uptime
#=============================================================================

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo "Status: UP"
