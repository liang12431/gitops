#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 打印说明：第一步先绕过 Ingress，直接通过 Service port-forward 测试应用。
echo "Testing via port-forward to Service first..."
# 把本机 18080 端口转发到 demo namespace 里的 Service/demo-api:8080，并把日志写入临时文件。
kubectl -n demo port-forward svc/demo-api 18080:8080 >/tmp/demo-api-port-forward.log 2>&1 &
# 记录刚才后台 port-forward 进程的 PID，后面脚本退出时要清理它。
PID=$!
# 注册退出钩子：无论脚本正常结束还是失败，都尝试停止 port-forward 后台进程。
trap 'kill "$PID" >/dev/null 2>&1 || true' EXIT
# 等待 3 秒，给 port-forward 建立连接的时间。
sleep 3
# 通过本机 18080 调用 /version，验证 Service 后面的应用是否正常。
curl -s http://127.0.0.1:18080/version
# 打印换行，让输出更清楚。
echo

# 打印说明：第二步通过 NGINX Ingress 入口测试。
echo "Testing via Ingress host demo.local..."
# 通过 Host header 模拟访问 demo.local；如果失败不让脚本退出，方便继续看到输出。
curl -s -H 'Host: demo.local' http://127.0.0.1/version || true
# 打印换行，让输出更清楚。
echo
