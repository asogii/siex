#!/bin/bash

# ================= 配置区域 =================
TEST_DIR="$(pwd)"
STARTUP_SCRIPT="$TEST_DIR/../startup"
TEST_ROOT="$TEST_DIR/temp_test_env"

export START_UP_PATH="$TEST_ROOT"
export START_UP_CONFIG_PATH="$TEST_ROOT/config"
export START_UP_KILL_WAIT_TIME=3
export START_UP_LOCK_TIMEOUT=2

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS] $1${NC}"; }
fail() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }
info() { echo -e "\n>> $1"; }

# ================= 环境准备 =================
info "Initializing Test Environment..."

if [ ! -f "$STARTUP_SCRIPT" ]; then fail "Startup script not found"; fi

rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/states"
mkdir -p "$TEST_ROOT/logs"

# 1. 基础 Worker
cat > "$TEST_DIR/dummy_worker.sh" << 'EOF'
#!/bin/bash
while true; do sleep 1; done
EOF
chmod +x "$TEST_DIR/dummy_worker.sh"

# 2. 参数检查 Worker
cat > "$TEST_DIR/arg_checker.sh" << 'EOF'
#!/bin/bash
echo "ARG_COUNT=$#"
echo "ARG_0=$0"
echo "ARG_1=<$1>"
while true; do sleep 1; done
EOF
chmod +x "$TEST_DIR/arg_checker.sh"

# 初始配置
cat > "$START_UP_CONFIG_PATH" <<EOF
local_app | $TEST_ROOT/logs/local.log | $TEST_DIR/dummy_worker.sh --env local
remote_app| $TEST_ROOT/logs/remote.log| @file://${TEST_DIR}/dummy_worker.sh --env downloaded
EOF

# ================= 测试执行 =================

# --- Test 1: Start ---
info "Test 1: Start local application"
"$STARTUP_SCRIPT" start local_app
PID_FILE="$TEST_ROOT/states/local_app.pid"
[ -f "$PID_FILE" ] && pass "App started" || fail "App failed to start"

# --- Test 2: Idempotency ---
info "Test 2: Idempotency check"
PID=$(cat "$PID_FILE" | cut -d: -f1)
"$STARTUP_SCRIPT" start local_app
NEW_PID=$(cat "$PID_FILE" | cut -d: -f1)
[ "$PID" == "$NEW_PID" ] && pass "Idempotency verified" || fail "Process restarted"

# --- Test 3: Ghost Recovery ---
info "Test 3: Ghost Process Recovery"
MARKER=$(cat "$PID_FILE" | cut -d: -f2)
echo ":$MARKER" > "$PID_FILE"
"$STARTUP_SCRIPT" status local_app
RECOVERED_PID=$(cat "$PID_FILE" | cut -d: -f1)
[ "$RECOVERED_PID" == "$PID" ] && pass "Ghost recovered" || fail "Recovery failed"

# --- Test 4: Remote Download ---
info "Test 4: Remote Download (@url)"
"$STARTUP_SCRIPT" start remote_app
R_PID_FILE="$TEST_ROOT/states/remote_app.pid"
if [ -f "$R_PID_FILE" ]; then
    pass "Remote App started"
else
    fail "Remote PID missing"
fi

# --- Test 5: Restart Logic ---
info "Test 5: Restart Logic"
OLD_PID=$(cat "$PID_FILE" | cut -d: -f1)
"$STARTUP_SCRIPT" restart local_app
sleep 1
NEW_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ "$OLD_PID" != "$NEW_PID" ] && ps -p "$NEW_PID" >/dev/null; then
    pass "Restart success (PID changed)"
else
    fail "Restart failed"
fi

# --- Test 6: Startup Run (CLI) & Lock Timeout ---
info "Test 6: 'startup run' & Lock Timeout"
LOCK_NAME="adhoc_task"
LOCK_DIR="$TEST_ROOT/states/$LOCK_NAME.lock"
mkdir -p "$LOCK_DIR" # 造一个死锁
sleep 3 # 等待超时(2s)

CMD_STR="$LOCK_NAME | $TEST_ROOT/logs/adhoc.log | $TEST_DIR/dummy_worker.sh --adhoc"
"$STARTUP_SCRIPT" run "$CMD_STR"

if [ -f "$TEST_ROOT/states/$LOCK_NAME.pid" ]; then
    pass "Lock broken & run success"
else
    fail "Lock timeout/run failed"
fi

# ==========================================
# [重要] 资源清理
# 在进行下一组测试前，停止所有当前运行的进程
# 防止 FreeBSD 环境下进程数过多导致 fork 失败
# =================
