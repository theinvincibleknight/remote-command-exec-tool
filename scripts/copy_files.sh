#!/bin/bash
#=============================================================================
# Script: copy_files.sh
# Description: Copy files/directories to a specific location on remote server
#              and set appropriate permissions.
# Usage:  This script runs ON the remote server after the file is copied.
#         It is called internally by remote_exec.sh --copy
#
# Standalone usage (on remote server):
#   ./copy_files.sh <dest_path> <owner:group> <permissions>
#=============================================================================

DEST_PATH="$1"
OWNERSHIP="${2:-root:root}"
PERMISSIONS="${3:-644}"

echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "---"

if [[ -z "$DEST_PATH" ]]; then
    echo "ERROR: Destination path required."
    echo "Usage: $0 <dest_path> [owner:group] [permissions]"
    exit 1
fi

if [[ -e "$DEST_PATH" ]]; then
    echo "File exists: $DEST_PATH"
    echo "Size: $(ls -lh "$DEST_PATH" | awk '{print $5}')"
    echo "Setting ownership to: $OWNERSHIP"
    sudo chown "$OWNERSHIP" "$DEST_PATH"
    echo "Setting permissions to: $PERMISSIONS"
    sudo chmod "$PERMISSIONS" "$DEST_PATH"
    echo ""
    echo "Final state:"
    ls -la "$DEST_PATH"
    echo ""
    echo "SUCCESS: File configured at $DEST_PATH"
else
    echo "ERROR: File not found at $DEST_PATH"
    exit 1
fi
