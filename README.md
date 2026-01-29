# Startup - A Simple & Robust Process Manager

**Startup** is a lightweight, zero-dependency process manager designed to ensure singleton execution of your services.

It supports **Linux** (Arch, Debian, CentOS, etc.) and **FreeBSD**.

## Key Features

* **Singleton Guarantee**: Uses UUID markers in process environments to strictly ensure only one instance of a service is running.
* **Atomic Locking**: Thread-safe start/stop operations to prevent race conditions.
* **Ghost Recovery**: Automatically detects and recovers control of processes even if the PID file is lost or corrupted.
* **Remote Execution**: Supports `@URL` syntax to download, execute, and auto-delete binary/scripts.
* **Bash Expansion**: Fully supports Bash syntax (e.g., `~`, `$HOME`, `$(date)`) in log paths and commands.

## Usage

* `startup start [NAME]...` - Start process(es).
* `startup stop [NAME]...` - Stop process(es).
* `startup restart [NAME]...` - Restart process(es).
* `startup status [NAME]...` - Show process status.
* `startup run "CONFIG_LINE"` - Run a process directly from a raw config string.

## Configuration

**Default Path:** `$HOME/.startup/config`
**Format:** `NAME | LOG_PATH | COMMAND`

### Examples

```text
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

