# siex

**siex** is a lightweight, pure Bash script, dependency-free process manager for Unix-like systems. It is designed to ensure **singleton execution**, idempotent startups, and robust ghost process recovery without requiring `root` or `systemd`.

Ideally suited for user-level services, background workers, and ad-hoc tasks in shared environments.

## Features

- **🔒 Atomic Locking**: Uses `mkdir` atomicity to prevent race conditions during concurrent starts.
- **👻 Ghost Recovery**: Smartly detects if a PID file belongs to a dead process (via UUID marking) and auto-recovers.
- **🛡️ Config Integrity**: Strictly prevents startup if duplicate service names or invalid characters are detected.
- **🌍 Shell Native**: correctly handles `$HOME` expansion, quotes, and complex arguments.
- **📥 Remote Binary**: Supports downloading binaries on-the-fly via `@url` syntax.
- **📦 Zero Dependencies**: Pure Bash. Works on Linux, FreeBSD.

## Installation

Simply download the script and give it execution permissions:

```bash
curl -o siex https://raw.githubusercontent.com/asogii/siex/main/siex
chmod +x siex
mv siex ~/bin/  # Optional: move to your path
```

## Configuration

The default configuration file is located at `~/.siex/config`.
Format: `service_name | log_path | command`

```text
# Example ~/.siex/config
# ============================================
# Basic Configuration
# ============================================

# Standard example: Absolute path logging
myweb | /var/log/myweb.log | node server.js

# Using Bash expansion ( ~, $HOME, Date )
# This creates a log file like: /home/user/logs/worker_2024-01-29.log
worker | ~/logs/worker_$(date +%F).log | python3 main.py

# ============================================
# Advanced Options
# ============================================

# [Log to /dev/null]
# Leave the middle part empty (or spaces) to disable logging
silent_task | | ./quiet_script.sh
# OR explicitly write /dev/null
null_task   | /dev/null | ./quiet_script.sh

# [Environment Variables]
# Use 'env' to pass variables to the process
prod_app | ~/logs/prod.log | env PORT=8080 ENV=production ./app_bin

# [Remote Execution]
# Download -> Run -> Delete
remote_job | ~/logs/remote.log | @http://192.168.1.1/script.sh --arg1

# ============================================
# Disabled / Comments
# ============================================

# Lines starting with # are ignored
# legacy_app | /tmp/old.log | ./old_bin
```

> **Note**: Service names must only contain `a-z`, `A-Z`, `0-9`, `_`, `-`, and `.`.

## Usage

### Start Services

    # Start all services in config
    siex start

    # Start specific service(s)
    siex start web_server data_worker

### Stop Services

    # Stop all running services
    siex stop

    # Stop specific service
    siex stop web_server

### Check Status

    siex status

### Restart

    siex restart web_server

### Run Ad-hoc Command
Execute a single command immediately (bypassing config file) with full locking and singleton protection:

    siex run "temp_job | temp.log | sleep 60"

## Environment Variables

You can customize **siex** by setting these environment variables:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `SIEX_PATH` | `~/.siex` | Root directory for state and config. |
| `SIEX_CONFIG_PATH` | `~/.siex/config` | Path to the configuration file. |
| `SIEX_KILL_WAIT_TIME` | `10` | Seconds to wait for graceful stop before `kill -9`. |
| `SIEX_LOCK_TIMEOUT` | `600` | Seconds before a stale lock file is forcibly broken. |
| `SIEX_LOG_TZ` | `[DEFAULT]` | Timezone used for log timestamps. |

## License

MIT License.
