#!/bin/bash
# 路径: test/test_suite.sh

# ================= 配置区域 =================
TEST_DIR="$(pwd)"
STARTUP_SCRIPT="$TEST_DIR/../startup"

# 设置测试沙盒目录
TEST_ROOT="$TEST_DIR/temp_test_env"
export START_UP_PATH="$TEST_ROOT"
export START_UP_CONFIG_PATH="$TEST_ROOT/config"
export START_UP_KILL_WAIT_TIME=3

# [新增] 设置锁超时时间为 2 秒，用于测试超时自动解锁
export START_UP_LOCK_TIMEOUT=2

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS] $1${NC}"; }
fail() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }
info() { echo -e "\n>> $1"; }

# ================= 环境准备 =================
info "Initializing Test Environment..."

if [ ! -f "$STARTUP_SCRIPT" ]; then fail "Startup script not found at ../startup"; fi

rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/states"
mkdir -p "$TEST_ROOT/logs"

chmod +x "$TEST_DIR/dummy_worker.sh"
chmod +x "$STARTUP_SCRIPT"

# 生成配置
FILE_URL="file://${TEST_DIR}/dummy_worker.sh"
cat > "$START_UP_CONFIG_PATH" <<EOF
local_app | $TEST_ROOT/logs/local.log | $TEST_DIR/dummy_worker.sh --env local
remote_app | $TEST_ROOT/logs/remote.log | @${FILE_URL} --env downloaded
EOF

info "Config generated. Lock Timeout set to: ${START_UP_LOCK_TIMEOUT}s"

# ================= 测试执行 =================

# --- Test 1: 本地启动 ---
info "Test 1: Start local application"
"$STARTUP_SCRIPT" start local_app
PID_FILE="$TEST_ROOT/states/local_app.pid"
if [ ! -f "$PID_FILE" ]; then fail "PID file missing"; fi
PID=$(cat "$PID_FILE" | cut -d: -f1)
if ps -p "$PID" > /dev/null; then pass "Local App started (PID: $PID)"; else fail "Process died"; fi

# --- Test 2: 幂等性 ---
info "Test 2: Idempotency check"
"$STARTUP_SCRIPT" start local_app
NEW_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ "$PID" == "$NEW_PID" ]; then pass "Idempotency verified"; else fail "Process restarted unexpectedly"; fi

# --- Test 3: 幽灵进程修复 ---
info "Test 3: Ghost Process Recovery"
MARKER=$(cat "$PID_FILE" | cut -d: -f2)
echo ":$MARKER" > "$PID_FILE"
"$STARTUP_SCRIPT" status local_app
RECOVERED_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ "$RECOVERED_PID" == "$PID" ]; then pass "Ghost recovered ($RECOVERED_PID)"; else fail "Recovery failed"; fi

# --- Test 4: 远程下载 (@URL) ---
info "Test 4: Remote Download (@url -> file://)"
"$STARTUP_SCRIPT" start remote_app
R_PID_FILE="$TEST_ROOT/states/remote_app.pid"
if [ -f "$R_PID_FILE" ]; then
    R_PID=$(cat "$R_PID_FILE" | cut -d: -f1)
    sleep 1 
    if ps -p "$R_PID" > /dev/null; then pass "Remote App running (PID: $R_PID)"; else fail "Remote process died"; fi
else fail "Remote PID file missing"; fi

# --- Test 5: Restart 逻辑 (新增) ---
info "Test 5: Restart Logic"
OLD_PID=$(cat "$PID_FILE" | cut -d: -f1)
"$STARTUP_SCRIPT" restart local_app
sleep 1

# 检查新 PID
NEW_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ -z "$NEW_PID" ]; then fail "Restart failed (No PID)"; fi

if [ "$OLD_PID" == "$NEW_PID" ]; then
    fail "Restart failed (PID did not change: $OLD_PID)"
elif ps -p "$NEW_PID" > /dev/null; then
    pass "Restart success (Old: $OLD_PID -> New: $NEW_PID)"
else
    fail "Restarted process is not running"
fi

# --- Test 6: Startup Run & Lock Timeout (新增) ---
info "Test 6: 'startup run' & Lock Timeout Logic"
LOCK_NAME="adhoc_task"
LOCK_DIR="$TEST_ROOT/states/$LOCK_NAME.lock"

# 1. 人为制造一个“死锁” (模拟上次崩溃残留的锁)
mkdir -p "$LOCK_DIR"
info "-> Created Dead Lock at: $(date +%T)"

# 2. 等待 3 秒 (超过设置的 2 秒超时时间)
echo "Waiting 3s for lock to expire..."
sleep 3

# 3. 使用 startup run 尝试运行 (应该自动破锁并运行)
# 注意：startup run 不需要配置文件，参数直接传
CMD_STR="$LOCK_NAME | $TEST_ROOT/logs/adhoc.log | $TEST_DIR/dummy_worker.sh --adhoc"
"$STARTUP_SCRIPT" run "$CMD_STR"

ADHOC_PID_FILE="$TEST_ROOT/states/$LOCK_NAME.pid"

if [ -f "$ADHOC_PID_FILE" ]; then
    A_PID=$(cat "$ADHOC_PID_FILE" | cut -d: -f1)
    if ps -p "$A_PID" > /dev/null; then
        pass "Lock broken & 'run' command success (PID: $A_PID)"
    else
        fail "Process started but died immediately"
    fi
else
    fail "Failed to break lock or start process (PID file missing)"
fi

# --- Test 7: 停止所有 ---
info "Test 7: Stop all"
"$STARTUP_SCRIPT" stop

sleep 1
if ps -p "$NEW_PID" > /dev/null 2>&1; then fail "Local app still alive"; fi
if ps -p "$R_PID" > /dev/null 2>&1; then fail "Remote app still alive"; fi
pass "All stopped"

# ================= 清理 =================
info "Teardown..."
rm -rf "$TEST_ROOT"

echo -e "\n${GREEN}All Tests Passed! Coverage: Start, Stop, Restart, Status, Run, Ghost, Lock, Remote.${NC}"

