#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 部署 gate-service 的 Deployment 和 Service。
kubectl apply -k "$ROOT/gitops/platform/gate-service"
# 等待 gate-service Deployment Ready。
kubectl -n demo rollout status deployment/gate-service --timeout=300s

# 输出 gate-service 安装完成和常用命令提示。
cat <<'MSG'

Gate service installed.

Open promotion:
  kubectl -n demo exec deploy/gate-service -- wget -qO- --post-data '' http://127.0.0.1:8080/gate/promotion/open

Check promotion:
  kubectl -n demo exec deploy/gate-service -- wget -qO- --post-data '' http://127.0.0.1:8080/gate/promotion/check
MSG
