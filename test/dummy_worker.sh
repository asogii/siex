#!/bin/bash
# 路径: test/dummy_worker.sh

echo "Dummy Worker Started!"
echo "Args received: $@"

# 模拟常驻进程
while true; do
    # 输出一点日志以便验证
    echo "[Worker] Running... $(date)"
    sleep 1
done

