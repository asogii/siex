#!/bin/bash
# 路径: test/test_suite.sh

# ================= 配置区域 =================
# 获取当前目录(test目录)的绝对路径
TEST_DIR="$(pwd)"
STARTUP_SCRIPT="$TEST_DIR/../startup"

# 设置测试沙盒目录
TEST_ROOT="$TEST_DIR/temp_test_env"
export START_UP_PATH="$TEST_ROOT"
export START_UP_CONFIG_PATH="$TEST_ROOT/config"
export START_UP_KILL_WAIT_TIME=3

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS] $1${NC}"; }
fail() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }
info() { echo -e "\n>> $1"; }

# ================= 环境准备 =================
info "Initializing Test Environment (No Python Dependency)..."

if [ ! -f "$STARTUP_SCRIPT" ]; then
    fail "Startup script not found at ../startup"
fi

# 1. 清理并创建沙盒
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/states"
mkdir -p "$TEST_ROOT/logs"

# 2. 确保依赖文件可执行
chmod +x "$TEST_DIR/dummy_worker.sh"
chmod +x "$STARTUP_SCRIPT"

# 3. 生成配置文件
# 关键修改：使用 file:// 协议模拟远程下载，无需启动 Web Server
# URL 格式: file:// + 绝对路径
FILE_URL="file://${TEST_DIR}/dummy_worker.sh"

cat > "$START_UP_CONFIG_PATH" <<EOF
# 本地测试任务
local_app | $TEST_ROOT/logs/local.log | $TEST_DIR/dummy_worker.sh --env local

# 远程下载测试任务 (使用 file:// 模拟)
remote_app | $TEST_ROOT/logs/remote.log | @${FILE_URL} --env downloaded
EOF

info "Config generated with URL: $FILE_URL"

# ================= 测试执行 =================

# --- Test 1: 本地启动 ---
info "Test 1: Start local application"
"$STARTUP_SCRIPT" start local_app

PID_FILE="$TEST_ROOT/states/local_app.pid"
if [ ! -f "$PID_FILE" ]; then fail "PID file missing"; fi

PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ -z "$PID" ]; then fail "PID is empty!"; fi

if ps -p "$PID" > /dev/null; then 
    pass "Local App started (PID: $PID)"
else 
    fail "Process died immediately (Check logs)"
fi

# --- Test 2: 幂等性 (重复启动) ---
info "Test 2: Idempotency check"
"$STARTUP_SCRIPT" start local_app
NEW_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ "$PID" == "$NEW_PID" ]; then
    pass "Idempotency verified"
else
    fail "Process restarted unexpectedly (Old: $PID, New: $NEW_PID)"
fi

# --- Test 3: 幽灵进程修复 ---
info "Test 3: Ghost Process Recovery"
# 仅保留UUID，删除PID
MARKER=$(cat "$PID_FILE" | cut -d: -f2)
echo ":$MARKER" > "$PID_FILE"

"$STARTUP_SCRIPT" status local_app

RECOVERED_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ "$RECOVERED_PID" == "$PID" ]; then
    pass "Ghost process recovered ($RECOVERED_PID)"
else
    fail "Recovery failed (Got: $RECOVERED_PID, Expected: $PID)"
fi

# --- Test 4: 远程下载 (@URL) ---
info "Test 4: Remote Download (@url -> file://)"
"$STARTUP_SCRIPT" start remote_app

# 检查二进制文件是否被清理
if ls "$TEST_ROOT/states/remote_app.bin" 1> /dev/null 2>&1; then
    fail "Binary file was NOT deleted!"
else
    pass "Binary file deleted (Security check passed)"
fi

R_PID_FILE="$TEST_ROOT/states/remote_app.pid"
if [ -f "$R_PID_FILE" ]; then
    R_PID=$(cat "$R_PID_FILE" | cut -d: -f1)
    if [ -z "$R_PID" ]; then fail "Remote PID is empty!"; fi
    
    # 增加等待，确保 sleep 0.5 生效后进程还在
    sleep 1 
    
    if ps -p "$R_PID" > /dev/null; then
        pass "Remote App running (PID: $R_PID)"
    else
        fail "Remote process died (Race condition check)"
    fi
else
    fail "Remote PID file missing"
fi

# --- Test 5: 停止测试 ---
info "Test 5: Stop all"
"$STARTUP_SCRIPT" stop

sleep 1
if ps -p "$PID" > /dev/null 2>&1; then fail "Local app still alive"; fi
if ps -p "$R_PID" > /dev/null 2>&1; then fail "Remote app still alive"; fi
pass "All stopped"

# ================= 清理 =================
info "Teardown..."
rm -rf "$TEST_ROOT"

echo -e "\n${GREEN}All Tests Passed!${NC}"

