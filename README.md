# Startup - A Simple & Robust Process Manager

**Startup** is a lightweight, zero-dependency process manager designed to ensure singleton execution of your services.

It supports **Linux** (Arch, Debian, CentOS, etc.) and **FreeBSD**, utilizing system-level markers to prevent duplicate processes and recover from PID file corruption.

## Key Features

* **Singleton Guarantee**: Uses UUID markers in process environments to strictly ensure only one instance of a service is running.
* **Atomic Locking**: Thread-safe start/stop operations to prevent race conditions.
* **Ghost Recovery**: Automatically detects and recovers control of processes even if the PID file is lost or corrupted.
* **Remote Execution**: Supports `@URL` syntax to download, execute, and auto-delete binary/scripts (Burn-after-reading mode).
* **Cross-Platform**: Native support for Linux (`/proc`) and FreeBSD (`procstat`).

## Usage

### Commands

-   `startup start [NAME]...`
    Start specified process(es). If no name is provided, starts all processes defined in the config.

-   `startup stop [NAME]...`
    Stop specified process(es). If no name is provided, stops all managed processes.

-   `startup restart [NAME]...`
    Restart specified process(es). Safely checks for config existence before stopping the current instance.

-   `startup status [NAME]...`
    Show the status (PID, Running/Down) of processes.

-   `startup run "CONFIG_LINE"`
    Directly run a process using a raw config string (useful for testing).
    Example: `startup run "test | /tmp/test.log | echo hello"`

## Configuration

**Default Path:** `$HOME/.startup/config`

The configuration file consists of lines describing processes.
**Note:** The separator is a pipe `|` to allow spaces in command arguments.

**Format:**
`NAME | LOG_PATH | COMMAND`

### Examples

```text
# Basic example (Absolute paths recommended)
myweb | /var/log/myweb.log | node /home/user/apps/server.js

# Using $HOME variable (Script will automatically expand it)
worker | $HOME/logs/worker.log | python3 main.py --env=prod --verbose

# Command with multiple arguments and spaces
db_proxy | $HOME/logs/proxy.log | ./proxy -c "conf/config with space.ini"

# Remote Execution (@URL)
# The script will: Download -> chmod +x -> Run -> Delete file
remote_task | $HOME/logs/task.log | @http://192.168.1.5/bin/worker --port 8080

