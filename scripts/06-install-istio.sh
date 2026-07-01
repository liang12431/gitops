#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 添加 Istio Helm 仓库。
helm repo add istio https://istio-release.storage.googleapis.com/charts
# 更新 Istio Helm 仓库索引。
helm repo update istio

# 安装或升级 Istio base chart：
# 主要包含 CRD 和集群级基础资源。
# --namespace istio-system：Istio 组件统一安装在 istio-system namespace。
# --create-namespace：如果 namespace 不存在，自动创建。
helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --create-namespace

# 安装或升级 istiod：
# istiod 是 Istio 控制面，负责把路由等配置下发给 Envoy。
# --wait：等待 Helm release 相关资源 Ready 后再继续。
helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --wait

# 安装或升级 Istio ingress gateway：
# gateway 是外部流量进入 Istio 网格的入口。
# service.type=NodePort：本地 OrbStack 用 NodePort 暴露，避免和 NGINX LoadBalancer 冲突。
# --wait：等待 gateway Ready 后再继续。
helm upgrade --install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --set service.type=NodePort \
  --wait

# 给 demo namespace 打标签，开启 Istio sidecar 自动注入。
kubectl label namespace demo istio-injection=enabled --overwrite
# 重启 demo-api，让新 Pod 被注入 istio-proxy sidecar。
kubectl -n demo rollout restart deployment/demo-api
# 等待 demo-api 重启完成。
kubectl -n demo rollout status deployment/demo-api --timeout=300s

# 部署 Istio Gateway；早期 baseline VirtualService 后续会被 Flagger 接管。
kubectl apply -k "$ROOT/gitops/platform/istio"

# 打印空行，让输出更容易阅读。
echo
# 打印 Istio gateway NodePort 标题。
echo "Istio gateway NodePort:"
# 查看 Istio ingress gateway 的 Service，重点看 http2 对应的 NodePort。
kubectl -n istio-system get svc istio-ingressgateway
# 打印空行，让输出更容易阅读。
echo
# 打印测试命令提示标题。
echo "Test command example:"
# 输出获取 Istio HTTP NodePort 的命令示例。
echo '  NODE_PORT=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath="{.spec.ports[?(@.name==\"http2\")].nodePort}")'
# 输出通过 Istio Gateway 访问 demo-api 的 curl 示例。
echo '  curl -H "Host: demo-istio.local" "http://127.0.0.1:${NODE_PORT}/version"'
