#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f "$ROOT/gitops/platform/namespaces/observability.yaml"
kubectl apply -k "$ROOT/gitops/platform/observability"
kubectl -n observability rollout status deployment/otel-collector --timeout=300s
kubectl -n observability rollout status deployment/prometheus --timeout=300s
kubectl -n observability rollout status deployment/grafana --timeout=300s

kubectl -n observability get deploy,svc,pod

cat <<'MSG'

Port-forward commands:
  kubectl -n observability port-forward svc/prometheus 9090:9090
  kubectl -n observability port-forward svc/grafana 3000:3000

Grafana login:
  admin / admin
MSG
