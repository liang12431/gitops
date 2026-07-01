#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 添加 ArgoCD Helm 仓库。
helm repo add argo https://argoproj.github.io/argo-helm
# 只更新 argo 这个 Helm 仓库，避免其它仓库网络问题影响安装。
helm repo update argo

# 安装或升级 ArgoCD：
# --namespace argocd：安装到 argocd namespace。
# --create-namespace：如果 namespace 不存在，自动创建。
# --set configs.params."server\\.insecure"=true：让 UI/API 用 HTTP 模式，方便本地 port-forward。
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set configs.params."server\\.insecure"=true

# 等待 ArgoCD UI/API 服务 Ready。
kubectl -n argocd rollout status deployment/argocd-server --timeout=420s
# 等待 ArgoCD repo-server Ready；它负责拉 Git 仓库和生成 manifests。
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=420s
# 等待 ArgoCD application-controller Ready；它负责同步 Kubernetes 资源。
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=420s

# 创建 demo-api 这个 ArgoCD Application，让 ArgoCD 开始管理 demo-api Deployment/Service/Ingress。
kubectl apply -f "$ROOT/gitops/argocd-apps/demo-api-application.yaml"

# 输出 ArgoCD 访问和密码读取方式。
cat <<'MSG'

ArgoCD is installed.

Port-forward:
  kubectl -n argocd port-forward svc/argocd-server 8081:80

Initial admin password:
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo

Application:
  demo-api
MSG
