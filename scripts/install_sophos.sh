#!/bin/bash
#=============================================================================
# Script: install_sophos.sh
# Description: Copies SophosSetup.sh to remote servers (from IP_List.txt),
#              uninstalls existing Sophos if present, installs fresh,
#              confirms installation, and cleans up.
# Usage: ./scripts/install_sophos.sh
#=============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALIASES_FILE="${SCRIPT_DIR}/ssh_aliases.conf"
IP_LIST_FILE="${SCRIPT_DIR}/IP_List.txt"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SOPHOS_FILE="/home/ubuntu/softs/SophosSetup.sh"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SCP_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTPUT_FILE="${OUTPUT_DIR}/sophos_install_${TIMESTAMP}.txt"
mkdir -p "$OUTPUT_DIR"

# Validate Sophos file exists on bastion
if [[ ! -f "$SOPHOS_FILE" ]]; then
    echo "ERROR: $SOPHOS_FILE not found on bastion host."
    exit 1
fi

# Get SSH credentials for an IP
get_creds() {
    grep -v "^#" "$ALIASES_FILE" | grep -v "^$" | grep "|${1}$" | head -1
}

# Read IPs
IP_LIST=$(grep -v "^#" "$IP_LIST_FILE" | grep -v "^$" | sed 's/[[:space:]]//g')
SERVER_COUNT=$(echo "$IP_LIST" | wc -l)

echo "============================================================================="
echo " Sophos Installation"
echo " Servers  : $SERVER_COUNT"
echo " Source   : $SOPHOS_FILE"
echo " Output   : $OUTPUT_FILE"
echo "============================================================================="
echo ""

cat <<EOF > "$OUTPUT_FILE"
=============================================================================
 Sophos Installation Report
 Date    : $(date '+%Y-%m-%d %H:%M:%S')
 Source  : $SOPHOS_FILE
 Servers : $SERVER_COUNT
=============================================================================

EOF

while IFS= read -r ip <&3; do
    [[ -z "$ip" ]] && continue

    echo "[INFO] Processing $ip..."

    # Get credentials
    creds=$(get_creds "$ip")
    if [[ -z "$creds" ]]; then
        echo "[ERROR] No credentials for $ip"
        echo "**** ${ip} ****" >> "$OUTPUT_FILE"
        echo "Status: SKIPPED - No SSH credentials found" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi

    pem=$(echo "$creds" | cut -d'|' -f2)
    user=$(echo "$creds" | cut -d'|' -f3)

    # Step 1: Copy SophosSetup.sh to remote /tmp
    echo "[INFO] Copying SophosSetup.sh to $ip:/tmp/..."
    if ! scp $SCP_OPTS -i "$pem" "$SOPHOS_FILE" "${user}@${ip}:/tmp/SophosSetup.sh" 2>/dev/null; then
        echo "[ERROR] Failed to copy to $ip (server may be DOWN)"
        echo "**** ${ip} ****" >> "$OUTPUT_FILE"
        echo "Status: DOWN / UNREACHABLE" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi

    # Step 2: Uninstall old, install new, confirm, cleanup
    echo "[INFO] Running install on $ip..."
    echo "**** ${ip} ****" >> "$OUTPUT_FILE"

    ssh $SSH_OPTS -i "$pem" "${user}@${ip}" bash -s << 'REMOTE_CMD' >> "$OUTPUT_FILE" 2>&1
echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Check if Sophos is already installed
if [ -d "/opt/sophos-spl" ]; then
    OLD_VERSION=$(sudo cat /opt/sophos-spl/base/VERSION.ini 2>/dev/null | grep PRODUCT_VERSION | awk -F'=' '{print $2}' | tr -d ' ')
    echo "Existing Sophos: FOUND"
    echo "Old Version: ${OLD_VERSION:-unknown}"
    echo "Uninstalling old Sophos..."
    sudo /opt/sophos-spl/bin/uninstall.sh --force 2>&1 | tail -3
    echo "Uninstall: DONE"
else
    echo "Existing Sophos: NOT FOUND"
fi

echo ""
echo "Installing Sophos..."
if sudo bash /tmp/SophosSetup.sh 2>&1 | tail -5; then
    echo ""
    if [ -d "/opt/sophos-spl" ]; then
        echo "INSTALL STATUS: SUCCESS"
        VERSION=$(sudo cat /opt/sophos-spl/base/VERSION.ini 2>/dev/null | grep PRODUCT_VERSION | awk -F'=' '{print $2}' | tr -d ' ')
        echo "Version: ${VERSION:-installed}"
    else
        echo "INSTALL STATUS: FAILED (/opt/sophos-spl not found after install)"
    fi
else
    echo ""
    echo "INSTALL STATUS: FAILED (installer error)"
fi

# Cleanup
echo ""
echo "Cleaning up /tmp/SophosSetup.sh..."
rm -f /tmp/SophosSetup.sh
echo "Cleanup: DONE"
REMOTE_CMD

    echo "" >> "$OUTPUT_FILE"
    echo "[DONE] $ip"
    echo ""

done 3<<< "$IP_LIST"

echo "============================================================================="
echo " Complete. Output saved to: $OUTPUT_FILE"
echo "============================================================================="
