#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 添加 ingress-nginx Helm 仓库；如果已存在，Helm 会复用或更新。
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# 更新 Helm 仓库索引，让本机知道 ingress-nginx 最新 chart 信息。
helm repo update
# 安装或升级 ingress-nginx controller：
# --namespace ingress-nginx：安装到 ingress-nginx namespace。
# --create-namespace：如果 namespace 不存在，自动创建。
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# 等待 ingress-nginx-controller Deployment 完成滚动发布，避免 admission webhook 未就绪。
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s
# 创建 demo namespace，后续 demo-api 部署在这里。
kubectl apply -f "$ROOT/gitops/platform/namespaces/demo.yaml"
# 部署 demo-api 的 Kubernetes baseline 资源：Deployment、Service、Ingress。
kubectl apply -k "$ROOT/gitops/applications/demo-api/overlays/local"
# 等待 demo-api Deployment Ready。
kubectl -n demo rollout status deployment/demo-api --timeout=180s

# 提醒如果使用域名访问，可以把 demo.local 加到本机 hosts。
echo "If needed, add this to /etc/hosts:"
# 打印 hosts 示例；当前脚本里的 smoke test 也可以直接用 Host header，不一定必须改 hosts。
echo "127.0.0.1 demo.local"
