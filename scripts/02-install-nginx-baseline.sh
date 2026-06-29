#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s
kubectl apply -f "$ROOT/gitops/platform/namespaces/demo.yaml"
kubectl apply -k "$ROOT/gitops/applications/demo-api/overlays/local"
kubectl -n demo rollout status deployment/demo-api --timeout=180s

echo "If needed, add this to /etc/hosts:"
echo "127.0.0.1 demo.local"
