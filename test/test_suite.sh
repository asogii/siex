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

# --- CLEANUP for Resource Limited Env ---
info "Cleaning up previous processes..."
"$STARTUP_SCRIPT" stop
sleep 2

# --- Test 7: Env Variable Expansion ($HOME) ---
info "Test 7: Environment Variable Expansion (\$HOME)"
# 这里使用 $HOME 变量，如果脚本不进行展开，就会报错找不到文件
cat > "$START_UP_CONFIG_PATH" <<EOF
env_expand_test | $TEST_ROOT/logs/env.log | \$HOME/dummy_link.sh
EOF

# 创建一个链接到 dummy_worker 的文件，放在 HOME 下测试
ln -sf "$TEST_DIR/dummy_worker.sh" "$HOME/dummy_link.sh"

"$STARTUP_SCRIPT" start env_expand_test
if [ -f "$TEST_ROOT/states/env_expand_test.pid" ]; then
    pass "Variable \$HOME expanded correctly"
else
    fail "Failed to expand \$HOME"
fi
rm -f "$HOME/dummy_link.sh"

# --- CLEANUP ---
info "Cleaning up..."
"$STARTUP_SCRIPT" stop
sleep 2

# --- Test 8 & 9: Argument Safety Check (Quotes) ---
info "Test 8 & 9: Argument Safety Check (Quotes & Spaces)"
cat > "$START_UP_CONFIG_PATH" <<EOF
arg_check | $TEST_ROOT/logs/arg.log | $TEST_DIR/arg_checker.sh "has space"
EOF
"$STARTUP_SCRIPT" start arg_check
sleep 1
LOG_CONTENT=$(cat "$TEST_ROOT/logs/arg.log")

if echo "$LOG_CONTENT" | grep -q "ARG_1=<has space>"; then
    pass "Arguments passed correctly (Quotes preserved)"
else
    echo "Log Content: $LOG_CONTENT"
    fail "Argument parsing failed (Quotes broken)"
fi

# --- CLEANUP ---
info "Cleaning up..."
"$STARTUP_SCRIPT" stop
sleep 2

# --- Test 11: Config Parsing Stress Test ---
info "Test 11: Configuration Parsing Stress Test"
cat > "$START_UP_CONFIG_PATH" <<EOF
   space_test    |    $TEST_ROOT/logs/space.log    |    $TEST_DIR/arg_checker.sh space_ok
$(echo -e "tab_test\t|\t$TEST_ROOT/logs/tab.log\t|\t$TEST_DIR/arg_checker.sh tab_ok")
empty_log || $TEST_DIR/dummy_worker.sh
pipe_in_cmd | $TEST_ROOT/logs/pipe.log | $TEST_DIR/arg_checker.sh "a|b"
# commented | log | cmd
EOF

info "-> Starting Stress Config..."
"$STARTUP_SCRIPT" start
sleep 1

# Check Space
if [ -f "$TEST_ROOT/states/space_test.pid" ]; then pass "Case 1: Spaces OK"; else fail "Case 1 Failed"; fi
# Check Tab
if [ -f "$TEST_ROOT/states/tab_test.pid" ]; then pass "Case 2: Tabs OK"; else fail "Case 2 Failed"; fi
# Check Empty Log
if [ -f "$TEST_ROOT/states/empty_log.pid" ] && [ ! -d "$TEST_ROOT/states/ " ]; then pass "Case 3: Empty Log OK"; else fail "Case 3 Failed"; fi
# Check Pipe in CMD
if grep -q "ARG_1=<a|b>" "$TEST_ROOT/logs/pipe.log"; then pass "Case 4: Pipe in CMD OK"; else fail "Case 4 Failed"; fi
# Check Comment
if [ ! -f "$TEST_ROOT/states/commented.pid" ]; then pass "Case 5: Comments Ignored"; else fail "Case 5 Failed"; fi

# --- Final Cleanup ---
info "Teardown..."
"$STARTUP_SCRIPT" stop
rm -rf "$TEST_ROOT"
rm -f "$TEST_DIR/dummy_worker.sh" "$TEST_DIR/arg_checker.sh"

echo -e "\n${GREEN}All Tests Passed! (Full Suite with Resource Cleanup)${NC}"

