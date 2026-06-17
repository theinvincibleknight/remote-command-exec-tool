#!/bin/bash
#=============================================================================
# Script: security_audit.sh
# Description: Basic security audit of the remote server
# Usage:  ./security_audit.sh
#=============================================================================

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "---"
echo "Security Audit Report"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# OS and Kernel
echo "=== OS & Kernel ==="
echo "OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "Kernel: $(uname -r)"
echo ""

# Last 10 logins
echo "=== Last 10 Logins ==="
last -10 | head -12
echo ""

# Failed login attempts
echo "=== Failed Login Attempts (last 24h) ==="
sudo grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 || echo "No failed attempts found or log not accessible"
echo ""

# Users with sudo access
echo "=== Users with Sudo Access ==="
grep -v "^#" /etc/sudoers 2>/dev/null | grep -v "^$" | head -10
getent group sudo 2>/dev/null || getent group wheel 2>/dev/null
echo ""

# Open ports
echo "=== Listening Ports ==="
sudo ss -tlnp 2>/dev/null || sudo netstat -tlnp 2>/dev/null
echo ""

# Pending security updates
echo "=== Pending Security Updates ==="
apt list --upgradable 2>/dev/null | grep -i security | head -10 || echo "None"
echo ""

# Check if unattended-upgrades is active
echo "=== Unattended Upgrades ==="
if dpkg -l | grep -q unattended-upgrades; then
    echo "Status: Installed"
    systemctl is-active unattended-upgrades 2>/dev/null && echo "Service: Active" || echo "Service: Inactive"
else
    echo "Status: NOT installed"
fi
echo ""

# SSH Configuration checks
echo "=== SSH Configuration ==="
echo "PermitRootLogin: $(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null || echo "not set (default)")"
echo "PasswordAuthentication: $(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null || echo "not set (default)")"
echo "PubkeyAuthentication: $(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config 2>/dev/null || echo "not set (default)")"
echo ""

# Firewall status
echo "=== Firewall Status ==="
if command -v ufw &>/dev/null; then
    sudo ufw status 2>/dev/null
else
    echo "UFW not installed"
    sudo iptables -L -n --line-numbers 2>/dev/null | head -20
fi
