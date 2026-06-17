# Code Explanation - RemoteCmdExec Framework

This document explains the logic and inner workings of every script in the framework.

---

## Table of Contents

1. [remote_exec.sh - Main Execution Engine](#remote_execsh---main-execution-engine)
2. [ssh_aliases.conf - Credentials Store](#ssh_aliasesconf---credentials-store)
3. [scripts/patch_and_reboot.sh - Patching Script](#scriptspatch_and_rebootsh---patching-script)
4. [scripts/check_uptime.sh - Uptime Checker](#scriptscheck_uptimesh---uptime-checker)
5. [scripts/install_sophos.sh - Sophos Installer](#scriptsinstall_sophossh---sophos-installer)
6. [scripts/server_info.sh - Server Information](#scriptsserver_infosh---server-information)
7. [scripts/disk_usage.sh - Disk Usage Monitor](#scriptsdisk_usagesh---disk-usage-monitor)
8. [scripts/install_package.sh - Package Installer](#scriptsinstall_packagesh---package-installer)
9. [scripts/service_status.sh - Service Status Checker](#scriptsservice_statussh---service-status-checker)
10. [scripts/security_audit.sh - Security Audit](#scriptssecurity_auditsh---security-audit)
11. [scripts/patch_server.sh - Detailed Patching](#scriptspatch_serversh---detailed-patching)
12. [scripts/copy_files.sh - File Permission Helper](#scriptscopy_filessh---file-permission-helper)
13. [Key Concepts and Gotchas](#key-concepts-and-gotchas)

---

## remote_exec.sh - Main Execution Engine

This is the brain of the framework. It reads target IPs, looks up credentials, connects to each server, and performs the requested action.

### Flow Diagram

```
User runs ./remote_exec.sh --cmd "uptime"
        │
        ▼
┌─────────────────────────┐
│  Parse CLI arguments     │  (--cmd, --script, --copy, --install, --patch, etc.)
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│  Validate inputs         │  (check action, file exists, required params)
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│  Read IP_List.txt        │  (skip comments #, skip blank lines, trim spaces)
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│  Create output file      │  (timestamped filename in output/ folder)
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│  Loop through each IP    │  (while read loop using heredoc <<<)
│  ┌───────────────────┐   │
│  │ get_ssh_credentials│   │  Look up PEM key + username from ssh_aliases.conf
│  │ validate PEM exists│   │  Check the .pem file is present on bastion
│  │ execute action     │   │  SSH/SCP to the remote server
│  │ capture output     │   │  Append to output file with **** IP **** header
│  └───────────────────┘   │
└───────────┬─────────────┘
            ▼
┌─────────────────────────┐
│  Write summary to output │
│  Print completion msg    │
└─────────────────────────┘
```

### Key Configuration Variables

```bash
set +e  # Do not exit on error - we handle errors per-server
```
- **Why `set +e`?** If one server fails (unreachable, bad key, etc.), we don't want the entire script to stop. Each server's result is handled independently.

```bash
SSH_OPTIONS="-n -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SCP_OPTIONS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
```

| Option | Purpose |
|--------|---------|
| `-n` | Redirects SSH stdin from /dev/null. **Critical** — prevents SSH from consuming the while loop's stdin (which contains remaining IPs). Only used for SSH, NOT SCP. |
| `-o StrictHostKeyChecking=no` | Skips the "Are you sure you want to connect?" prompt for new hosts. Needed for non-interactive execution. |
| `-o ConnectTimeout=10` | If a server doesn't respond within 10 seconds, skip it instead of hanging forever. |
| `-o BatchMode=yes` | Disables password prompts. If key auth fails, it immediately errors out instead of waiting for manual input. |

### Function: get_ssh_credentials()

```bash
get_ssh_credentials() {
    local target_ip="$1"
    result=$(grep -v "^#" "$ALIASES_FILE" | grep -v "^$" | grep "|${target_ip}$" | head -1)
    # Returns: /path/to/key.pem|username
}
```

**Logic:**
1. Read `ssh_aliases.conf`, skip comments (`^#`) and blank lines (`^$`)
2. Search for lines ending with `|<target_ip>` (the `$` ensures exact IP match at end of line)
3. Take the first match (`head -1`) in case of duplicates
4. Extract field 2 (PEM path) and field 3 (username) using `cut -d'|'`

### Function: execute_on_server()

This is where the actual remote work happens. It takes 5 parameters:

```bash
execute_on_server "$ip" "$ACTION" "$PARAM" "${EXTRA_PARAM:-$SCRIPT_ARGS}" "$OUTPUT_FILE"
```

**Actions explained:**

#### cmd (inline command)
```bash
$ssh_cmd "$param" >> "$output_file" 2>&1
```
- Runs the command string directly via SSH
- Captures both stdout and stderr to the output file

#### script (run a local script remotely)
```bash
# Step 1: Copy script to remote /tmp with unique name
$scp_cmd "$param" "${user}@${ip}:${remote_tmp}"

# Step 2: Make executable, run, cleanup
$ssh_cmd "chmod +x ${remote_tmp} && ${remote_tmp} ${extra_param}; rm -f ${remote_tmp}"
```
- SCP copies the script to `/tmp/<script_name>_<unix_timestamp>` on the remote server
- SSH then makes it executable, runs it (passing any extra args), and deletes it
- The `;` (not `&&`) before `rm -f` ensures cleanup happens even if the script fails

#### copy (transfer files)
```bash
$scp_cmd -r "$local_path" "${user}@${ip}:${remote_dest}"
```
- Uses `-r` for recursive copy (works for both files and directories)

#### install (apt-get packages)
```bash
$ssh_cmd "sudo apt-get update -qq && sudo apt-get install -y ${packages}"
```
- Updates package list quietly (`-qq`), then installs with `-y` (auto-yes)

#### patch (system upgrade)
```bash
$ssh_cmd "sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y"
```
- Full update → upgrade → cleanup cycle

### The While Loop (stdin issue)

```bash
while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    execute_on_server ...
done <<< "$IP_ADDRESSES"
```

**Why `<<<` (here-string) instead of pipe?**

```bash
# BAD - runs loop in a subshell, variables lost after loop
echo "$IP_ADDRESSES" | while read -r ip; do ...

# GOOD - loop runs in current shell
while IFS= read -r ip; do ... done <<< "$IP_ADDRESSES"
```

**Why `-n` in SSH_OPTIONS?**

Without `-n`, SSH inherits stdin from the while loop. SSH reads stdin looking for input — and what's in stdin? The remaining IP addresses! SSH eats them, the loop has nothing left to read, and only the first server gets processed.

```
IP_ADDRESSES = "172.18.82.132\n172.18.82.110\n10.17.7.10"
                     ↑
              while reads this first
              then SSH (without -n) reads the rest → loop ends prematurely
```

Adding `-n` tells SSH: "Don't touch stdin, read from /dev/null instead."

---

## ssh_aliases.conf - Credentials Store

```
alias-name|/full/path/to/key.pem|username|ip-address
```

**Format:** Pipe-delimited, 4 fields per line.

| Field | Description | Example |
|-------|-------------|---------|
| 1 | Alias name (for reference) | ssh-broker-uat-1 |
| 2 | Full path to PEM key | /home/ubuntu/AWS_KPs/UAT_Broker_Layer_Applications.pem |
| 3 | SSH username | ubuntu |
| 4 | Server IP address | 172.18.82.132 |

**Lookup logic:** The scripts search for the target IP in field 4 (anchored to end of line with `$`) and extract fields 2 and 3 for authentication.

---

## scripts/patch_and_reboot.sh - Patching Script

**Runs on:** Remote server (via remote_exec.sh)

### Flow

```
Step 1: Print server identity (hostname, IP, kernel, uptime)
    │
    ▼
Step 2: sudo apt update -y
    │   (shows last 3 lines of output)
    ▼
Step 3: Hold critical packages
    │   dpkg --get-selections | grep -E 'mongo|mysql|java|python|docker'
    │   sudo apt-mark hold <packages>
    ▼
Step 4: sudo apt-get upgrade -y
    │   (shows last 5 lines)
    │
    ├── SUCCESS → Step 5: Reboot
    │
    └── FAILED  → Exit (no reboot)
```

### Key Logic

```bash
HOLD_PKGS=$(dpkg --get-selections | grep -E 'mongo|mysql|java|python|docker' | awk '{print $1}')
```

- `dpkg --get-selections` — Lists all installed packages with their state (install/hold/deinstall)
- `grep -E 'mongo|mysql|java|python|docker'` — Filters packages matching these keywords
- `awk '{print $1}'` — Extracts just the package name (first column)
- `sudo apt-mark hold $HOLD_PKGS` — Marks them as "held" so apt-get upgrade skips them

```bash
if sudo apt-get upgrade -y 2>&1 | tail -5; then
```

- `tail -5` — Only captures last 5 lines of upgrade output (keeps log clean)
- The `if` checks the exit code of the pipeline
- If upgrade succeeds (exit 0) → reboot
- If it fails → print FAILED and `exit 1` (no reboot)

```bash
rm -f "$0" 2>/dev/null
sudo reboot
```

- `$0` — The currently running script's path (the temp copy in /tmp)
- Deletes itself before rebooting so nothing is left behind

**Important:** When `sudo reboot` runs, the SSH connection gets killed. This makes `remote_exec.sh` see a non-zero exit code and log `[ERROR]` on the console — but the patching was successful. Always verify via the output file.

---

## scripts/check_uptime.sh - Uptime Checker

**Runs on:** Remote server (via remote_exec.sh)

```bash
echo "Hostname: $(hostname)"
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo "Status: UP"
```

**Logic:** If the script executes at all, the server is UP. If the server is down, the SCP step in `remote_exec.sh` will fail and write `Status: DOWN / UNREACHABLE` to the output.

| Command | Output |
|---------|--------|
| `hostname` | Server hostname (e.g., AWQPBROAUL01) |
| `hostname -I \| awk '{print $1}'` | First IP address assigned to the host |
| `uname -r` | Kernel version (e.g., 6.8.0-1053-aws) |
| `uptime -p` | Human-readable uptime (e.g., "up 3 minutes") |

---

## scripts/install_sophos.sh - Sophos Installer

**Runs on:** Bastion host (standalone — NOT through remote_exec.sh)

### Why Standalone?

This script needs to:
1. Read `ssh_aliases.conf` (on bastion)
2. SCP a 19MB file to each remote server
3. SSH and run install commands

If you ran it through `remote_exec.sh`, it would be copied to the remote server where none of these bastion-local files exist.

### Flow

```
Bastion Host                          Remote Server
─────────────                         ─────────────
Read IP_List.txt
    │
    ▼
For each IP:
    │
    ├── SCP SophosSetup.sh ──────────→ /tmp/SophosSetup.sh
    │
    ├── SSH bash -s << heredoc ──────→ Execute on remote:
    │                                     1. Check /opt/sophos-spl exists?
    │                                     2. If yes: read VERSION.ini, uninstall
    │                                     3. sudo bash /tmp/SophosSetup.sh
    │                                     4. Verify /opt/sophos-spl created
    │                                     5. Read new VERSION.ini
    │                                     6. rm /tmp/SophosSetup.sh
    │
    ├── Capture output ←─────────────── stdout/stderr
    │
    ▼
Save to output/sophos_install_<timestamp>.txt
```

### Key Techniques

#### File Descriptor 3 for Loop

```bash
while IFS= read -r ip <&3; do
    ...
    ssh $SSH_OPTS -i "$pem" "${user}@${ip}" bash -s << 'REMOTE_CMD'
    ...
    REMOTE_CMD
done 3<<< "$IP_LIST"
```

**Problem:** SSH with heredoc reads from stdin (fd 0). The while loop also reads from stdin. They conflict.

**Solution:** Read the loop input from file descriptor 3 (`<&3` / `3<<<`), leaving stdin (fd 0) free for the SSH heredoc.

#### No `-n` in SSH_OPTS

Unlike `remote_exec.sh`, this script does NOT use `-n` in SSH_OPTS because:
- `-n` redirects stdin from `/dev/null`
- But `bash -s << 'REMOTE_CMD'` sends the script content via stdin
- With `-n`, SSH would ignore the heredoc content → empty output

#### Quoted Heredoc

```bash
ssh ... bash -s << 'REMOTE_CMD'
echo "Hostname: $(hostname)"
REMOTE_CMD
```

The quotes around `'REMOTE_CMD'` prevent the bastion from expanding variables. `$(hostname)` is executed on the **remote server**, not on the bastion.

Without quotes:
```bash
ssh ... bash -s << REMOTE_CMD
echo "Hostname: $(hostname)"  # Expands on BASTION → wrong hostname!
REMOTE_CMD
```

#### Version Extraction

```bash
sudo cat /opt/sophos-spl/base/VERSION.ini 2>/dev/null | grep PRODUCT_VERSION | awk -F'=' '{print $2}' | tr -d ' '
```

The VERSION.ini file format is:
```
PRODUCT_NAME = SPL-Base-Component
PRODUCT_VERSION = 1.6.0.290
BUILD_DATE = 2026-04-13
```

- `grep PRODUCT_VERSION` — Get the version line
- `awk -F'=' '{print $2}'` — Split by `=`, take the value part (` 1.6.0.290`)
- `tr -d ' '` — Remove spaces → `1.6.0.290`
- `sudo` — The file is readable only by root

---

## scripts/server_info.sh - Server Information

**Runs on:** Remote server (via remote_exec.sh)

Collects comprehensive server info:

| Command | What it gets |
|---------|-------------|
| `hostname` | Server hostname |
| `hostname -I \| awk '{print $1}'` | Primary private IP |
| `uptime \| awk ... \| sed ...` | Uptime duration |
| `lsb_release -ds` | OS name and version |
| `uname -r` | Kernel version |
| `nproc` | Number of CPU cores |
| `free -h \| awk '/^Mem:/{print $2}'` | Total RAM |
| `free -h \| awk '/^Mem:/{print $3}'` | Used RAM |
| `df -h / \| tail -1` | Root filesystem usage |

---

## scripts/disk_usage.sh - Disk Usage Monitor

**Runs on:** Remote server (via remote_exec.sh)

### Logic

```bash
THRESHOLD="${1:-80}"  # Default 80%, can pass custom via --args
```

1. Prints all non-tmpfs filesystems sorted by usage (highest first)
2. Loops through each filesystem, checks if usage % ≥ threshold
3. Prints `[ALERT]` for any exceeding the threshold
4. Shows top 10 largest directories in `/` using `sudo du -sh /*`

```bash
while IFS= read -r line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')  # Extract "82" from "82%"
    if [[ "$usage" -ge "$THRESHOLD" ]]; then
        echo "  [ALERT] $line"
    fi
done <<< "$(df -h | grep -v 'tmpfs\|udev\|Filesystem')"
```

---

## scripts/install_package.sh - Package Installer

**Runs on:** Remote server (via remote_exec.sh)

```bash
PACKAGES="$1"  # Received via --args "nginx curl wget"
```

1. Validates that packages argument is not empty
2. Runs `sudo apt-get update -qq` (quiet mode)
3. Runs `sudo apt-get install -y $PACKAGES`
4. On success, loops through each package and prints its installed version:

```bash
for pkg in $PACKAGES; do
    version=$(dpkg -l "$pkg" 2>/dev/null | grep "^ii" | awk '{print $3}')
done
```

- `dpkg -l` lists packages with their status
- `^ii` means "installed" (first `i` = desired state, second `i` = actual state)
- Field 3 is the version number

---

## scripts/service_status.sh - Service Status Checker

**Runs on:** Remote server (via remote_exec.sh)

```bash
SERVICES="$1"
# If no argument, defaults to:
SERVICES="ssh nginx apache2 mysql mongod docker redis-server cron"
```

For each service:
```bash
systemctl list-unit-files | grep -q "^${svc}"     # Check if service exists
systemctl is-active "$svc"                          # active/inactive/failed
systemctl is-enabled "$svc"                         # enabled/disabled
```

Only prints services that actually exist on the system (skips those not installed).

---

## scripts/security_audit.sh - Security Audit

**Runs on:** Remote server (via remote_exec.sh)

Checks multiple security aspects:

| Check | Command | What to look for |
|-------|---------|-----------------|
| OS/Kernel | `lsb_release -ds`, `uname -r` | Outdated kernel versions |
| Last logins | `last -10` | Unexpected login sources |
| Failed logins | `grep "Failed password" /var/log/auth.log` | Brute force attempts |
| Sudo users | `/etc/sudoers`, `getent group sudo` | Unauthorized sudo access |
| Open ports | `ss -tlnp` | Unexpected listening services |
| Pending updates | `apt list --upgradable \| grep security` | Unpatched vulnerabilities |
| Unattended upgrades | `dpkg -l \| grep unattended-upgrades` | Auto-patch status |
| SSH config | grep sshd_config | Root login, password auth enabled? |
| Firewall | `ufw status` | Firewall active/inactive |

---

## scripts/patch_server.sh - Detailed Patching

**Runs on:** Remote server (via remote_exec.sh)

A more detailed patching script with options:

```bash
--security-only    # Only install security updates (not all upgrades)
--reboot           # Automatically reboot if /var/run/reboot-required exists
```

**Differences from patch_and_reboot.sh:**
- Does NOT hold packages (installs everything)
- Shows list of upgradable packages before upgrading
- Runs `dist-upgrade` in addition to `upgrade` (handles dependency changes)
- Runs `autoremove` and `autoclean` for cleanup
- Only reboots if kernel requires it AND `--reboot` flag is set
- Does NOT reboot by default

---

## scripts/copy_files.sh - File Permission Helper

**Runs on:** Remote server (via remote_exec.sh)

A helper script to set ownership and permissions on files that were copied to the remote server.

```bash
./remote_exec.sh --script scripts/copy_files.sh --args "/etc/myapp/app.conf root:root 644"
```

Arguments:
- `$1` — File path on remote server
- `$2` — Owner:Group (default: root:root)
- `$3` — Permissions (default: 644)

```bash
sudo chown "$OWNERSHIP" "$DEST_PATH"
sudo chmod "$PERMISSIONS" "$DEST_PATH"
ls -la "$DEST_PATH"  # Confirm final state
```

---

## Key Concepts and Gotchas

### 1. SSH stdin Consumption

**Problem:** SSH reads from stdin by default. When SSH runs inside a `while read` loop, it consumes the remaining loop input (IP addresses).

**Solutions used:**
- `remote_exec.sh`: Uses `-n` flag in SSH_OPTIONS → SSH reads from /dev/null
- `install_sophos.sh`: Uses file descriptor 3 for the loop (`read <&3` / `done 3<<<`) → stdin stays free for SSH heredoc

### 2. SCP Does Not Support `-n`

**Problem:** `-n` is SSH-specific. Passing it to SCP causes errors.

**Solution:** Separate `SSH_OPTIONS` (with `-n`) and `SCP_OPTIONS` (without `-n`).

### 3. Reboot Causes False ERROR

**Problem:** `sudo reboot` kills the SSH connection → SSH exits with non-zero code → script logs ERROR.

**Reality:** The patching was successful. The reboot terminated the connection before SSH could cleanly close.

**How to verify:** Check the output file for `PATCH STATUS: SUCCESS`.

### 4. Heredoc Quoting

```bash
# Variables expand on REMOTE server (correct):
ssh ... bash -s << 'EOF'
echo $(hostname)
EOF

# Variables expand on LOCAL bastion (wrong):
ssh ... bash -s << EOF
echo $(hostname)
EOF
```

Always quote the heredoc delimiter when you want commands to run on the remote server.

### 5. Script Cleanup After Reboot

When `patch_and_reboot.sh` runs, it's stored as `/tmp/patch_and_reboot.sh_<timestamp>`. Since it calls `rm -f "$0"` before `sudo reboot`, the script deletes itself. Even if it didn't, `/tmp` is cleaned on most Ubuntu systems during boot.

### 6. Parallel vs Sequential

- **Sequential (default):** Servers processed one by one. Safe for patching, installations, and operations that need careful monitoring.
- **Parallel:** All servers processed simultaneously as background jobs. Good for read-only operations (uptime check, disk usage) but NOT recommended for patching or installations (output from multiple servers may interleave in the output file).

### 7. Output File Naming Convention

```
output/<action>_<detail>_<YYYYMMDD_HHMMSS>.txt
```

Examples:
- `cmd_output_20260615_064219.txt`
- `script_patch_and_reboot_20260615_120619.txt`
- `sophos_install_20260616_120410.txt`

Each server's output block starts with `**** <IP> ****` for easy parsing and identification.
