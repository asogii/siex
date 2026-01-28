#!/bin/bash
# 路径: test/test_suite.sh

# ================= 配置区域 =================
# 获取当前目录(test目录)的绝对路径
TEST_DIR="$(pwd)"
# 主脚本在上一级目录
STARTUP_SCRIPT="$TEST_DIR/../startup"

# 设置测试沙盒目录 (在 test/temp_test_env 下生成)
TEST_ROOT="$TEST_DIR/temp_test_env"
export START_UP_PATH="$TEST_ROOT"
export START_UP_CONFIG_PATH="$TEST_ROOT/config"
export START_UP_KILL_WAIT_TIME=3

# 模拟远程服务器
MOCK_PORT=8899
MOCK_HOST="http://127.0.0.1:$MOCK_PORT"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS] $1${NC}"; }
fail() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }
info() { echo -e "\n>> $1"; }

# ================= 环境准备 =================
info "Initializing Test Environment..."

# 1. 检查主脚本是否存在
if [ ! -f "$STARTUP_SCRIPT" ]; then
    fail "Startup script not found at ../startup"
fi

# 2. 清理并创建沙盒
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT/states"
mkdir -p "$TEST_ROOT/logs"

# 3. 确保 dummy_worker 可执行
chmod +x "$TEST_DIR/dummy_worker.sh"
chmod +x "$STARTUP_SCRIPT"

# 4. 启动本地 Mock Server (模拟 GitHub raw 访问)
# 在当前 test 目录下启动，这样 http://localhost/dummy_worker.sh 就能被访问到
info "Starting Mock HTTP Server..."
python3 -m http.server $MOCK_PORT --bind 127.0.0.1 >/dev/null 2>&1 &
MOCK_PID=$!
sleep 1

# 5. 生成配置文件
# 注意：v12.0 要求绝对路径。
# 我们用 $TEST_DIR/dummy_worker.sh 指向本地文件
# 用 @URL 指向远程文件
cat > "$START_UP_CONFIG_PATH" <<EOF
# 本地测试任务
local_app | $TEST_ROOT/logs/local.log | $TEST_DIR/dummy_worker.sh --env local

# 远程下载测试任务 (@URL)
remote_app | $TEST_ROOT/logs/remote.log | @$MOCK_HOST/dummy_worker.sh --env downloaded
EOF

info "Config generated:"
cat "$START_UP_CONFIG_PATH"

# ================= 测试执行 =================

# --- Test 1: 本地启动 ---
info "Test 1: Start local application"
"$STARTUP_SCRIPT" start local_app

PID_FILE="$TEST_ROOT/states/local_app.pid"
if [ ! -f "$PID_FILE" ]; then fail "PID file missing"; fi

PID=$(cat "$PID_FILE" | cut -d: -f1)
if ps -p "$PID" > /dev/null; then 
    pass "Local App started (PID: $PID)"
else 
    fail "Process died immediately"
fi

# --- Test 2: 幂等性 (重复启动) ---
info "Test 2: Idempotency check"
"$STARTUP_SCRIPT" start local_app
NEW_PID=$(cat "$PID_FILE" | cut -d: -f1)
if [ "$PID" == "$NEW_PID" ]; then
    pass "Idempotency verified"
else
    fail "Process restarted unexpectedly"
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
    fail "Recovery failed"
fi

# --- Test 4: 远程下载 (@URL) ---
info "Test 4: Remote Download (@url)"
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
    if ps -p "$R_PID" > /dev/null; then
        pass "Remote App running (PID: $R_PID)"
    else
        fail "Remote process not running"
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
kill $MOCK_PID 2>/dev/null
rm -rf "$TEST_ROOT"

echo -e "\n${GREEN}All Tests Passed!${NC}"

