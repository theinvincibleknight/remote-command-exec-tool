#!/bin/bash
#=============================================================================
# Remote Command Execution Script
# Description: Execute commands, scripts, copy files, install packages,
#              and patch servers remotely from the Bastion host.
# Usage:       ./remote_exec.sh [OPTIONS]
#=============================================================================

set +e  # Do not exit on error - we handle errors per-server

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALIASES_FILE="${SCRIPT_DIR}/ssh_aliases.conf"
DEFAULT_IP_LIST="${SCRIPT_DIR}/IP_List.txt"
OUTPUT_DIR="${SCRIPT_DIR}/output"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
SSH_OPTIONS="-n -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SCP_OPTIONS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

#-----------------------------------------------------------------------------
# Color Codes
#-----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#-----------------------------------------------------------------------------
# Functions
#-----------------------------------------------------------------------------

usage() {
    cat <<EOF
${CYAN}=============================================================================
 Remote Command Execution Framework
=============================================================================${NC}

${GREEN}USAGE:${NC}
    ./remote_exec.sh [OPTIONS]

${GREEN}OPTIONS:${NC}
    --cmd "<command>"       Run an inline command on remote servers
    --script <path>        Run a local script on remote servers
    --copy <local_path>    Copy a file/directory to remote servers
    --dest <remote_path>   Destination path on remote servers (used with --copy)
    --install <packages>   Install packages on remote servers (apt-get)
    --patch                Update and upgrade remote servers (apt-get)
    --iplist <file>        Use a custom IP list file (default: IP_List.txt)
    --outdir <path>        Custom output directory (default: output/)
    --args "<arguments>"   Arguments to pass to the script
    --parallel             Run on all servers in parallel (default: sequential)
    --dry-run              Show what would be executed without running
    --help                 Show this help message

${GREEN}EXAMPLES:${NC}
    # Get server info from all servers in IP_List.txt
    ./remote_exec.sh --script scripts/server_info.sh

    # Run a command on all servers
    ./remote_exec.sh --cmd "df -h && free -m"

    # Copy a file to all servers
    ./remote_exec.sh --copy /tmp/config.yml --dest /etc/app/config.yml

    # Install packages
    ./remote_exec.sh --install "nginx curl wget"

    # Patch all servers
    ./remote_exec.sh --patch

    # Use custom IP list and run in parallel
    ./remote_exec.sh --script scripts/server_info.sh --iplist prod_ips.txt --parallel

EOF
    exit 0
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

#-----------------------------------------------------------------------------
# Lookup SSH credentials from ssh_aliases.conf based on IP
# Returns: PEM_KEY|USER
#-----------------------------------------------------------------------------
get_ssh_credentials() {
    local target_ip="$1"
    local result=""

    # Search in ssh_aliases.conf for the IP
    result=$(grep -v "^#" "$ALIASES_FILE" | grep -v "^$" | grep "|${target_ip}$" | head -1)

    if [[ -n "$result" ]]; then
        local pem_key=$(echo "$result" | cut -d'|' -f2)
        local user=$(echo "$result" | cut -d'|' -f3)
        echo "${pem_key}|${user}"
    else
        echo ""
    fi
}

#-----------------------------------------------------------------------------
# Read IP list from file (skip comments and blank lines)
#-----------------------------------------------------------------------------
read_ip_list() {
    local ip_file="$1"

    if [[ ! -f "$ip_file" ]]; then
        log_error "IP list file not found: $ip_file"
        exit 1
    fi

    grep -v "^#" "$ip_file" | grep -v "^$" | sed 's/[[:space:]]//g'
}

#-----------------------------------------------------------------------------
# Execute command on a single remote server
#-----------------------------------------------------------------------------
execute_on_server() {
    local ip="$1"
    local action="$2"
    local param="$3"
    local extra_param="$4"
    local output_file="$5"

    # Get SSH credentials
    local creds=$(get_ssh_credentials "$ip")

    if [[ -z "$creds" ]]; then
        log_error "No SSH credentials found for IP: $ip"
        echo "**** ${ip} ****" >> "$output_file"
        echo "ERROR: No SSH credentials found for this IP in ssh_aliases.conf" >> "$output_file"
        echo "" >> "$output_file"
        return 1
    fi

    local pem_key=$(echo "$creds" | cut -d'|' -f1)
    local user=$(echo "$creds" | cut -d'|' -f2)

    # Validate PEM key exists
    if [[ ! -f "$pem_key" ]]; then
        log_error "PEM key not found: $pem_key (for IP: $ip)"
        echo "**** ${ip} ****" >> "$output_file"
        echo "ERROR: PEM key not found: $pem_key" >> "$output_file"
        echo "" >> "$output_file"
        return 1
    fi

    local ssh_cmd="ssh ${SSH_OPTIONS} -i ${pem_key} ${user}@${ip}"
    local scp_cmd="scp ${SCP_OPTIONS} -i ${pem_key}"

    log_info "Connecting to ${user}@${ip}..."

    case "$action" in
        cmd)
            # Run inline command
            echo "**** ${ip} ****" >> "$output_file"
            if $ssh_cmd "$param" >> "$output_file" 2>&1; then
                log_success "Command executed successfully on $ip"
            else
                log_error "Command failed on $ip (exit code: $?)"
                echo "EXIT CODE: $?" >> "$output_file"
            fi
            echo "" >> "$output_file"
            ;;

        script)
            # Copy script to remote, execute, capture output, cleanup
            local script_name=$(basename "$param")
            local remote_tmp="/tmp/${script_name}_$(date +%s)"

            # Copy script to remote server
            if ! $scp_cmd "$param" "${user}@${ip}:${remote_tmp}" 2>/dev/null; then
                log_error "Failed to copy script to $ip (server may be DOWN)"
                echo "**** ${ip} ****" >> "$output_file"
                echo "Status: DOWN / UNREACHABLE" >> "$output_file"
                echo "" >> "$output_file"
                return 1
            fi

            # Make executable and run
            echo "**** ${ip} ****" >> "$output_file"
            if $ssh_cmd "chmod +x ${remote_tmp} && ${remote_tmp} ${extra_param}; rm -f ${remote_tmp}" >> "$output_file" 2>&1; then
                log_success "Script executed successfully on $ip"
            else
                log_error "Script execution failed on $ip"
                echo "EXIT CODE: $?" >> "$output_file"
                # Cleanup remote temp file
                $ssh_cmd "rm -f ${remote_tmp}" 2>/dev/null
            fi
            echo "" >> "$output_file"
            ;;

        copy)
            # Copy file to remote server
            local local_path="$param"
            local remote_dest="$extra_param"

            echo "**** ${ip} ****" >> "$output_file"
            if $scp_cmd -r "$local_path" "${user}@${ip}:${remote_dest}" 2>&1 | tee -a "$output_file"; then
                log_success "File copied successfully to $ip:${remote_dest}"
                echo "SUCCESS: Copied $(basename "$local_path") to ${remote_dest}" >> "$output_file"
            else
                log_error "Failed to copy file to $ip"
                echo "ERROR: Failed to copy file" >> "$output_file"
            fi
            echo "" >> "$output_file"
            ;;

        install)
            # Install packages via apt-get
            local packages="$param"
            echo "**** ${ip} ****" >> "$output_file"
            if $ssh_cmd "sudo apt-get update -qq && sudo apt-get install -y ${packages}" >> "$output_file" 2>&1; then
                log_success "Packages installed successfully on $ip"
            else
                log_error "Package installation failed on $ip"
                echo "EXIT CODE: $?" >> "$output_file"
            fi
            echo "" >> "$output_file"
            ;;

        patch)
            # Update and upgrade the server
            echo "**** ${ip} ****" >> "$output_file"
            if $ssh_cmd "sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y" >> "$output_file" 2>&1; then
                log_success "Server patched successfully: $ip"
            else
                log_error "Patching failed on $ip"
                echo "EXIT CODE: $?" >> "$output_file"
            fi
            echo "" >> "$output_file"
            ;;
    esac
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

# Default values
ACTION=""
PARAM=""
EXTRA_PARAM=""
IP_LIST_FILE="$DEFAULT_IP_LIST"
CUSTOM_OUTDIR=""
SCRIPT_ARGS=""
PARALLEL=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd)
            ACTION="cmd"
            PARAM="$2"
            shift 2
            ;;
        --script)
            ACTION="script"
            PARAM="$2"
            shift 2
            ;;
        --copy)
            ACTION="copy"
            PARAM="$2"
            shift 2
            ;;
        --dest)
            EXTRA_PARAM="$2"
            shift 2
            ;;
        --install)
            ACTION="install"
            PARAM="$2"
            shift 2
            ;;
        --patch)
            ACTION="patch"
            shift
            ;;
        --iplist)
            IP_LIST_FILE="$2"
            shift 2
            ;;
        --outdir)
            CUSTOM_OUTDIR="$2"
            shift 2
            ;;
        --args)
            SCRIPT_ARGS="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate action
if [[ -z "$ACTION" ]]; then
    log_error "No action specified. Use --cmd, --script, --copy, --install, or --patch"
    echo ""
    usage
fi

# Validate specific options
if [[ "$ACTION" == "copy" && -z "$EXTRA_PARAM" ]]; then
    log_error "--copy requires --dest <remote_path>"
    exit 1
fi

if [[ "$ACTION" == "script" && ! -f "$PARAM" ]]; then
    log_error "Script not found: $PARAM"
    exit 1
fi

# Set output directory
if [[ -n "$CUSTOM_OUTDIR" ]]; then
    OUTPUT_DIR="$CUSTOM_OUTDIR"
fi
mkdir -p "$OUTPUT_DIR"

# Generate output filename with timestamp
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
case "$ACTION" in
    cmd)     OUTPUT_FILE="${OUTPUT_DIR}/cmd_output_${TIMESTAMP}.txt" ;;
    script)  OUTPUT_FILE="${OUTPUT_DIR}/script_$(basename "$PARAM" .sh)_${TIMESTAMP}.txt" ;;
    copy)    OUTPUT_FILE="${OUTPUT_DIR}/copy_output_${TIMESTAMP}.txt" ;;
    install) OUTPUT_FILE="${OUTPUT_DIR}/install_output_${TIMESTAMP}.txt" ;;
    patch)   OUTPUT_FILE="${OUTPUT_DIR}/patch_output_${TIMESTAMP}.txt" ;;
esac

# Read IP list
IP_ADDRESSES=$(read_ip_list "$IP_LIST_FILE")

if [[ -z "$IP_ADDRESSES" ]]; then
    log_error "No IPs found in $IP_LIST_FILE. Add server IPs (one per line)."
    exit 1
fi

# Count servers
SERVER_COUNT=$(echo "$IP_ADDRESSES" | wc -l)

# Print execution summary
echo -e "${CYAN}=============================================================================${NC}"
echo -e "${CYAN} Remote Command Execution${NC}"
echo -e "${CYAN}=============================================================================${NC}"
echo -e " Action     : ${GREEN}${ACTION}${NC}"
echo -e " Target IPs : ${GREEN}${IP_LIST_FILE} (${SERVER_COUNT} servers)${NC}"
echo -e " Output     : ${GREEN}${OUTPUT_FILE}${NC}"
if [[ -n "$PARAM" ]]; then
    echo -e " Parameter  : ${GREEN}${PARAM}${NC}"
fi
if [[ -n "$EXTRA_PARAM" ]]; then
    echo -e " Extra Param: ${GREEN}${EXTRA_PARAM}${NC}"
fi
if [[ -n "$SCRIPT_ARGS" ]]; then
    echo -e " Script Args: ${GREEN}${SCRIPT_ARGS}${NC}"
fi
echo -e " Mode       : ${GREEN}$(if $PARALLEL; then echo "Parallel"; else echo "Sequential"; fi)${NC}"
echo -e "${CYAN}=============================================================================${NC}"
echo ""

# Dry run mode
if $DRY_RUN; then
    log_warning "DRY RUN MODE - No commands will be executed"
    echo ""
    echo "Would execute on the following servers:"
    echo "$IP_ADDRESSES" | while read -r ip; do
        local_creds=$(get_ssh_credentials "$ip")
        if [[ -n "$local_creds" ]]; then
            echo "  ✓ $ip (credentials found)"
        else
            echo "  ✗ $ip (NO credentials found)"
        fi
    done
    exit 0
fi

# Write output file header
cat <<EOF > "$OUTPUT_FILE"
=============================================================================
 Remote Execution Report
 Date      : $(date '+%Y-%m-%d %H:%M:%S')
 Action    : ${ACTION}
 Parameter : ${PARAM:-N/A}
 IP List   : ${IP_LIST_FILE}
 Servers   : ${SERVER_COUNT}
=============================================================================

EOF

# Execute on each server
SUCCESS_COUNT=0
FAIL_COUNT=0

if $PARALLEL; then
    # Parallel execution
    log_info "Starting parallel execution on ${SERVER_COUNT} servers..."
    PIDS=()

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        execute_on_server "$ip" "$ACTION" "$PARAM" "${EXTRA_PARAM:-$SCRIPT_ARGS}" "$OUTPUT_FILE" &
        PIDS+=($!)
    done <<< "$IP_ADDRESSES"

    # Wait for all background jobs
    for pid in "${PIDS[@]}"; do
        wait "$pid" 2>/dev/null
    done
else
    # Sequential execution
    log_info "Starting sequential execution on ${SERVER_COUNT} servers..."
    echo ""

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if execute_on_server "$ip" "$ACTION" "$PARAM" "${EXTRA_PARAM:-$SCRIPT_ARGS}" "$OUTPUT_FILE"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done <<< "$IP_ADDRESSES"
fi

# Summary
echo ""
echo -e "${CYAN}=============================================================================${NC}"
echo -e "${CYAN} Execution Complete${NC}"
echo -e "${CYAN}=============================================================================${NC}"
echo -e " Output saved to: ${GREEN}${OUTPUT_FILE}${NC}"
echo -e " Total servers  : ${SERVER_COUNT}"
echo -e "${CYAN}=============================================================================${NC}"
echo ""

# Append summary to output file
cat <<EOF >> "$OUTPUT_FILE"

=============================================================================
 Execution Summary
 Completed : $(date '+%Y-%m-%d %H:%M:%S')
 Total     : ${SERVER_COUNT} servers
=============================================================================
EOF

log_success "Output saved to: ${OUTPUT_FILE}"
