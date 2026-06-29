#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set configs.params."server\\.insecure"=true

kubectl -n argocd rollout status deployment/argocd-server --timeout=420s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=420s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=420s

kubectl apply -f "$ROOT/gitops/argocd-apps/demo-api-application.yaml"

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

