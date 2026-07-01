#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 创建 observability namespace。
kubectl apply -f "$ROOT/gitops/platform/namespaces/observability.yaml"
# 部署观测组件：OTel Collector、Prometheus、Grafana。
kubectl apply -k "$ROOT/gitops/platform/observability"
# 等待 OTel Collector Ready，它负责接收应用 OTLP traces/metrics。
kubectl -n observability rollout status deployment/otel-collector --timeout=300s
# 等待 Prometheus Ready，它负责抓取 /actuator/prometheus 和 OTel Collector 指标。
kubectl -n observability rollout status deployment/prometheus --timeout=300s
# 等待 Grafana Ready，它负责展示 Prometheus 数据。
kubectl -n observability rollout status deployment/grafana --timeout=300s

# 打印 observability namespace 下的 Deployment、Service、Pod，方便确认资源状态。
kubectl -n observability get deploy,svc,pod

# 输出后续访问 Prometheus/Grafana 的提示信息。
cat <<'MSG'

Port-forward commands:
  kubectl -n observability port-forward svc/prometheus 9090:9090
  kubectl -n observability port-forward svc/grafana 3000:3000

Grafana login:
  admin / admin
MSG
