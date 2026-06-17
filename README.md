# RemoteCmdExec - Remote Command Execution Framework

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Execute commands, scripts, copy files, install software, and patch servers remotely from a Bastion host.

## Folder Structure

```
RemoteCmdExec/
├── README.md                       # Documentation
├── remote_exec.sh                  # Main execution engine
├── ssh_aliases.conf                # SSH credentials mapping (alias|pem|user|ip)
├── IP_List.txt                     # Target server IPs (one per line)
├── scripts/                        # Scripts to run on remote servers
│   ├── check_uptime.sh             # Check if server is up after reboot
│   ├── copy_files.sh               # Set permissions after file copy
│   ├── disk_usage.sh               # Check disk usage with threshold alerts
│   ├── install_package.sh          # Install packages via apt-get
│   ├── install_sophos.sh           # Sophos agent install (standalone)
│   ├── patch_and_reboot.sh         # Patch and reboot servers
│   ├── patch_server.sh             # Detailed patching (security-only option)
│   ├── security_audit.sh           # Basic security audit
│   ├── server_info.sh              # Collect server details
│   └── service_status.sh           # Check service statuses
└── output/                         # Execution output (auto-generated)
```

## Setup

1. Copy this folder to your Bastion host:
   ```bash
   scp -r RemoteCmdExec/ bastion-host:~/scripts/
   ```

2. Make scripts executable:
   ```bash
   chmod +x ~/scripts/RemoteCmdExec/remote_exec.sh
   chmod +x ~/scripts/RemoteCmdExec/scripts/*.sh
   ```

3. Add target server IPs to `IP_List.txt` (one per line):
   ```
   172.18.82.132
   172.18.82.110
   10.17.7.10
   ```

4. Ensure PEM keys have correct permissions:
   ```bash
   chmod 400 ~/AWS_KPs/*.pem
   ```

---

## remote_exec.sh - Main Execution Engine

The main script that handles running commands, scripts, copying files, installing packages, and patching across all servers listed in `IP_List.txt`.

### Options

| Option | Description |
|--------|-------------|
| `--cmd "<command>"` | Run an inline command on remote servers |
| `--script <path>` | Run a local script on remote servers |
| `--copy <local_path>` | Copy a file/directory to remote servers |
| `--dest <remote_path>` | Destination path on remote (used with --copy) |
| `--install <packages>` | Install packages via apt-get |
| `--patch` | Update and upgrade remote servers |
| `--iplist <file>` | Use a custom IP list file |
| `--outdir <path>` | Custom output directory |
| `--args "<arguments>"` | Arguments to pass to the script |
| `--parallel` | Run on all servers in parallel |
| `--dry-run` | Preview without executing |
| `--help` | Show help |

### Examples

```bash
# Run inline command
./remote_exec.sh --cmd "uptime && df -h"

# Run inline command with custom IP list
./remote_exec.sh --cmd "free -m" --iplist prod_servers.txt

# Copy a config file to all servers
./remote_exec.sh --copy /tmp/nginx.conf --dest /etc/nginx/nginx.conf

# Install packages on all servers
./remote_exec.sh --install "htop curl wget"

# Quick patch (without script)
./remote_exec.sh --patch

# Dry run to verify credentials
./remote_exec.sh --cmd "echo hello" --dry-run

# Run in parallel (good for read-only commands)
./remote_exec.sh --cmd "uptime" --parallel
```

---

## Scripts

### check_uptime.sh
Check if a server is up after a reboot. Returns hostname, IP, kernel, and uptime. If the server is unreachable, the output shows `DOWN / UNREACHABLE`.

```bash
# Check uptime on all servers in IP_List.txt
./remote_exec.sh --script scripts/check_uptime.sh

# Typical use: run 1-2 minutes after patching to confirm servers are back up
./remote_exec.sh --script scripts/check_uptime.sh
```

**Sample Output:**
```
**** 172.18.82.132 ****
Hostname: AWQPBROAUL01
Private IP: 172.18.82.132
Kernel: 6.8.0-1053-aws
Uptime: up 3 minutes
Status: UP

**** 10.17.7.10 ****
Status: DOWN / UNREACHABLE
```

---

### patch_and_reboot.sh
Patch servers by holding critical packages (mongo, mysql, java, python, docker), running apt upgrade, and rebooting.

```bash
# Patch and reboot all servers in IP_List.txt
./remote_exec.sh --script scripts/patch_and_reboot.sh

# After 1-2 minutes, check if servers are back up
./remote_exec.sh --script scripts/check_uptime.sh
```

**What it does:**
1. Runs `apt update`
2. Holds packages matching: mongo, mysql, java, python, docker
3. Runs `apt-get upgrade -y`
4. Reboots the server (if patch succeeds)

**Sample Output:**
```
**** 10.17.7.10 ****
Hostname: AWQPFNSAUL01
Private IP: 10.17.7.10
Kernel: 6.8.0-1053-aws
Uptime (before patch): up 4 weeks, 5 hours, 23 minutes
Date: 2026-06-15 12:06:20
---
[12:06:20] Running apt update...
[12:06:25] Holding packages:
  - docker-ce
  - python3
  - mysql-client-8.0
[12:06:25] Running apt-get upgrade...
[12:07:24] PATCH STATUS: SUCCESS
[12:07:24] Cleaning up and rebooting server...
```

**Note:** Console may show `[ERROR]` for some servers — this is expected when the reboot terminates the SSH connection before it closes gracefully. Check the output file for `PATCH STATUS: SUCCESS` to confirm patching worked.

---

### install_sophos.sh
Install/reinstall Sophos agent on remote servers. This is a **standalone script** (run directly, NOT through `remote_exec.sh`).

```bash
# Install Sophos on all servers in IP_List.txt
./scripts/install_sophos.sh
```

**What it does:**
1. Copies `/home/ubuntu/softs/SophosSetup.sh` to remote `/tmp/`
2. Checks if Sophos is already installed (`/opt/sophos-spl`)
3. If found → captures old version and uninstalls
4. Installs fresh using `sudo bash /tmp/SophosSetup.sh`
5. Confirms installation and prints new version
6. Cleans up setup file from remote `/tmp/`

**Sample Output:**
```
**** 10.17.7.10 ****
Hostname: AWLOYALAPL01
Private IP: 10.17.7.10
Date: 2026-06-16 12:05:31
---
Existing Sophos: FOUND
Old Version: 1.5.0.280
Uninstalling old Sophos...
Uninstall: DONE

Installing Sophos...
Successfully verified connection to Sophos Central
Successfully registered with Sophos Central
Successfully installed product on 2026-06-16 12:06:17

INSTALL STATUS: SUCCESS
Version: 1.6.0.290

Cleaning up /tmp/SophosSetup.sh...
Cleanup: DONE
```

**Important:** Run this directly (`./scripts/install_sophos.sh`), NOT via `./remote_exec.sh --script`. It handles SCP + SSH internally.

---

### server_info.sh
Collect detailed server information including hostname, IP, uptime, OS, kernel, CPU, memory, and disk usage.

```bash
./remote_exec.sh --script scripts/server_info.sh
```

**Sample Output:**
```
**** 172.18.82.132 ****
Hostname: AWQPBROAUL01
Private IP: 172.18.82.132
Uptime: 12 days
OS: Ubuntu 22.04.4 LTS
Kernel: 6.8.0-1053-aws
CPU Cores: 4
Memory Total: 16Gi
Memory Used: 8.2Gi
Disk Usage (/):
  Total: 80G, Used: 32G, Available: 44G, Use%: 43%
```

---

### disk_usage.sh
Check disk usage across all partitions with configurable threshold alerts.

```bash
# Default threshold: 80%
./remote_exec.sh --script scripts/disk_usage.sh

# Custom threshold: alert if any partition > 90%
./remote_exec.sh --script scripts/disk_usage.sh --args "90"
```

**Sample Output:**
```
**** 172.18.82.132 ****
Hostname: AWQPBROAUL01
Private IP: 172.18.82.132
---
Disk Usage Report (Alert threshold: 80%)

All Filesystems:
Filesystem      Size  Used Avail Use% Mounted on
/dev/root        80G   62G   14G  82% /
/dev/xvda16     881M  162M  657M  20% /boot

Partitions exceeding 80% usage:
  [ALERT] /dev/root        80G   62G   14G  82% /

Top 10 largest directories in /:
6.2G    /var
4.1G    /usr
2.3G    /opt
```

---

### install_package.sh
Install one or more packages on remote servers via apt-get.

```bash
# Install a single package
./remote_exec.sh --script scripts/install_package.sh --args "nginx"

# Install multiple packages
./remote_exec.sh --script scripts/install_package.sh --args "htop curl wget net-tools"
```

**Sample Output:**
```
**** 172.18.82.132 ****
Hostname: AWQPBROAUL01
Private IP: 172.18.82.132
---
Installing packages: nginx curl
[12:30:15] Updating package list...
[12:30:20] Installing: nginx curl
[12:30:35] SUCCESS: Packages installed successfully.
Installed versions:
  nginx: 1.18.0-6ubuntu14.4
  curl: 7.81.0-1ubuntu1.15
```

---

### service_status.sh
Check the status of services running on remote servers.

```bash
# Check default services (ssh, nginx, apache2, mysql, mongod, docker, redis, cron)
./remote_exec.sh --script scripts/service_status.sh

# Check specific services
./remote_exec.sh --script scripts/service_status.sh --args "nginx docker mongod"
```

**Sample Output:**
```
**** 172.18.82.132 ****
Hostname: AWQPBROAUL01
Private IP: 172.18.82.132
---
Service Status Report

SERVICE                   STATUS       ENABLED
-------                   ------       -------
ssh                       active       enabled
nginx                     active       enabled
docker                    active       enabled
mongod                    inactive     disabled
cron                      active       enabled

System Load: 0.15 0.10 0.05
Running Processes: 142
```

---

### security_audit.sh
Run a basic security audit on remote servers — checks logins, open ports, SSH config, firewall, and pending security updates.

```bash
./remote_exec.sh --script scripts/security_audit.sh
```

**Sample Output:**
```
**** 172.18.82.132 ****
Hostname: AWQPBROAUL01
Private IP: 172.18.82.132
---
Security Audit Report
Date: 2026-06-15 14:00:00

=== OS & Kernel ===
OS: Ubuntu 22.04.4 LTS
Kernel: 6.8.0-1053-aws

=== Last 10 Logins ===
ubuntu   pts/0   172.18.82.132   Mon Jun 15 12:00

=== Failed Login Attempts (last 24h) ===
No failed attempts found or log not accessible

=== Listening Ports ===
LISTEN  0  128  0.0.0.0:22    users:(("sshd",pid=1234))
LISTEN  0  128  0.0.0.0:443   users:(("nginx",pid=5678))

=== SSH Configuration ===
PermitRootLogin: no
PasswordAuthentication: no
PubkeyAuthentication: yes

=== Firewall Status ===
Status: active
To                         Action      From
22/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
```

---

### patch_server.sh
Detailed patching script with options for security-only updates and optional reboot.

```bash
# Full system upgrade (no reboot)
./remote_exec.sh --script scripts/patch_server.sh

# Security updates only
./remote_exec.sh --script scripts/patch_server.sh --args "--security-only"

# Full upgrade with auto-reboot if required
./remote_exec.sh --script scripts/patch_server.sh --args "--reboot"

# Security only + reboot if needed
./remote_exec.sh --script scripts/patch_server.sh --args "--security-only --reboot"
```

**Note:** For standard patching workflow (hold packages + upgrade + reboot), use `patch_and_reboot.sh` instead.

---

### copy_files.sh
Helper script that runs on the remote server after a file is copied — sets ownership and permissions.

```bash
# Copy a file then set permissions
./remote_exec.sh --copy /tmp/app.conf --dest /etc/myapp/app.conf
# Then run copy_files.sh to set ownership/permissions
./remote_exec.sh --script scripts/copy_files.sh --args "/etc/myapp/app.conf root:root 644"
```

**Arguments:** `<dest_path> [owner:group] [permissions]`

---

## SSH Aliases Configuration

The `ssh_aliases.conf` file uses a pipe-delimited format:
```
alias-name|/full/path/to/key.pem|username|ip-address
```

Example:
```
ssh-broker-uat-1|/home/ubuntu/AWS_KPs/UAT_Broker_Layer_Applications.pem|ubuntu|172.18.82.132
```

---

## Output

All outputs are saved in the `output/` folder with timestamped filenames:
- `cmd_output_20260615_064219.txt`
- `script_patch_and_reboot_20260615_120619.txt`
- `sophos_install_20260616_120410.txt`

Each server's output is separated by:
```
**** <IP Address> ****
```

---

## Common Workflow: Monthly Patching

```bash
# 1. Add servers to patch in IP_List.txt
vi IP_List.txt

# 2. Dry run to verify all servers are reachable
./remote_exec.sh --cmd "echo ok" --dry-run

# 3. Get pre-patch server info
./remote_exec.sh --script scripts/server_info.sh

# 4. Patch and reboot
./remote_exec.sh --script scripts/patch_and_reboot.sh

# 5. Wait 1-2 minutes, then verify servers are back up
./remote_exec.sh --script scripts/check_uptime.sh

# 6. Verify services are running post-patch
./remote_exec.sh --script scripts/service_status.sh --args "nginx docker"
```

## Tips

- Use `--dry-run` to validate IP list and credential mapping before execution
- Use `--parallel` for read-only operations (uptime, disk check, service status)
- Use sequential mode (default) for patching and installations
- Console `[ERROR]` after patching with reboot is expected (SSH connection killed by reboot)
- Check the output file for actual `PATCH STATUS` to confirm success
- `install_sophos.sh` runs directly — not through `remote_exec.sh`
