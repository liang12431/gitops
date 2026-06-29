#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -k "$ROOT/gitops/platform/gate-service"
kubectl -n demo rollout status deployment/gate-service --timeout=300s

cat <<'MSG'

Gate service installed.

Open promotion:
  kubectl -n demo exec deploy/gate-service -- wget -qO- --method=PUT http://127.0.0.1:8080/gate/promotion/open

Check promotion:
  kubectl -n demo exec deploy/gate-service -- wget -qO- --method=POST http://127.0.0.1:8080/gate/promotion/check
MSG

