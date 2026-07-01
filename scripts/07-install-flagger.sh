#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 添加 Flagger Helm 仓库。
helm repo add flagger https://flagger.app
# 更新 Flagger Helm 仓库索引。
helm repo update flagger

# 安装或升级 Flagger controller：
# --namespace flagger-system：安装到 flagger-system namespace。
# --create-namespace：如果 namespace 不存在，自动创建。
# meshProvider=istio：告诉 Flagger 使用 Istio 控制流量。
# metricsServer=http://prometheus.observability:9090：告诉 Flagger 去本地 Prometheus 查询指标。
helm upgrade --install flagger flagger/flagger \
  --namespace flagger-system \
  --create-namespace \
  --set meshProvider=istio \
  --set metricsServer=http://prometheus.observability:9090

# 安装或升级 Flagger loadtester：
# loadtester 用于需要压测/探测时发请求。
# --namespace flagger-system：安装到 flagger-system namespace。
# --create-namespace：如果 namespace 不存在，自动创建。
helm upgrade --install flagger-loadtester flagger/loadtester \
  --namespace flagger-system \
  --create-namespace

# 等待 Flagger controller Ready。
kubectl -n flagger-system rollout status deployment/flagger --timeout=300s
# 等待 Flagger loadtester Ready。
kubectl -n flagger-system rollout status deployment/flagger-loadtester --timeout=300s

# The manual Istio VirtualService was only for the baseline Istio test.
# Flagger will own the canary VirtualService for demo-api.
# 删除手工创建的 demo-api VirtualService，避免和 Flagger 后续生成的 VirtualService 冲突。
kubectl -n demo delete virtualservice demo-api --ignore-not-found=true

# 创建 demo-api-canary 这个 ArgoCD Application，让 ArgoCD 管理 Flagger Canary CR。
kubectl apply -f "$ROOT/gitops/argocd-apps/demo-api-canary-application.yaml"

# 输出安装完成和检查命令提示。
cat <<'MSG'

Flagger installed.

Check:
  kubectl -n flagger-system get pods
  kubectl -n demo get canary
  kubectl -n demo describe canary demo-api
MSG
