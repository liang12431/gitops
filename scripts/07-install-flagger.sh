#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm repo add flagger https://flagger.app
helm repo update flagger

helm upgrade --install flagger flagger/flagger \
  --namespace flagger-system \
  --create-namespace \
  --set meshProvider=istio \
  --set metricsServer=http://prometheus.observability:9090

helm upgrade --install flagger-loadtester flagger/loadtester \
  --namespace flagger-system \
  --create-namespace

kubectl -n flagger-system rollout status deployment/flagger --timeout=300s
kubectl -n flagger-system rollout status deployment/flagger-loadtester --timeout=300s

# The manual Istio VirtualService was only for the baseline Istio test.
# Flagger will own the canary VirtualService for demo-api.
kubectl -n demo delete virtualservice demo-api --ignore-not-found=true

kubectl apply -f "$ROOT/gitops/argocd-apps/demo-api-canary-application.yaml"

cat <<'MSG'

Flagger installed.

Check:
  kubectl -n flagger-system get pods
  kubectl -n demo get canary
  kubectl -n demo describe canary demo-api
MSG

