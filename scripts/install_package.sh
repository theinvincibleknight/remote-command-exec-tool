#!/bin/bash
#=============================================================================
# Script: install_package.sh
# Description: Install one or more packages on the remote server
# Usage:  ./install_package.sh "package1 package2 package3"
#=============================================================================

PACKAGES="$1"

if [[ -z "$PACKAGES" ]]; then
    echo "ERROR: No packages specified."
    echo "Usage: $0 \"package1 package2\""
    exit 1
fi

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "---"
echo "Installing packages: ${PACKAGES}"
echo ""

# Update package list
echo "[$(date '+%H:%M:%S')] Updating package list..."
sudo apt-get update -qq 2>&1

# Install packages
echo "[$(date '+%H:%M:%S')] Installing: ${PACKAGES}"
if sudo apt-get install -y $PACKAGES 2>&1; then
    echo ""
    echo "[$(date '+%H:%M:%S')] SUCCESS: Packages installed successfully."
    echo "Installed versions:"
    for pkg in $PACKAGES; do
        version=$(dpkg -l "$pkg" 2>/dev/null | grep "^ii" | awk '{print $3}')
        if [[ -n "$version" ]]; then
            echo "  $pkg: $version"
        fi
    done
else
    echo ""
    echo "[$(date '+%H:%M:%S')] ERROR: Package installation failed."
    exit 1
fi
