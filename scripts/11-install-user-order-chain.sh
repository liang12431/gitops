#!/usr/bin/env bash
# 创建 user-service、order-api、order-api-canary 三个 ArgoCD Application。
# 真正的 Deployment/Service/Canary 仍由 ArgoCD 从 GitOps 目录同步。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 创建 user-service Application。
kubectl apply -f "$ROOT/gitops/argocd-apps/user-service-application.yaml"
# 创建 order-api Application。
kubectl apply -f "$ROOT/gitops/argocd-apps/order-api-application.yaml"
# 创建 order-api-canary Application。
kubectl apply -f "$ROOT/gitops/argocd-apps/order-api-canary-application.yaml"

# 本地 OrbStack Pod 访问 GitHub 可能 EOF，所以创建后马上切到本地 Git mirror。
"$ROOT/scripts/09-use-local-git-mirror.sh"

# 输出检查命令。
cat <<'MSG'

User/order ArgoCD Applications installed.

Check:
  kubectl -n argocd get applications user-service order-api order-api-canary
  kubectl -n demo get deploy,svc,canary | grep -E 'user-service|order-api'

Test through Istio:
  NODE_PORT=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
  curl -s -H 'Host: user.local' "http://127.0.0.1:${NODE_PORT}/user/1"
  curl -s -H 'Host: user.local' "http://127.0.0.1:${NODE_PORT}/user/2"
  curl -s -H 'Host: user.local' "http://127.0.0.1:${NODE_PORT}/user/3"
MSG

