#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update istio

helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --create-namespace

helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --wait

helm upgrade --install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --set service.type=NodePort \
  --wait

kubectl label namespace demo istio-injection=enabled --overwrite
kubectl -n demo rollout restart deployment/demo-api
kubectl -n demo rollout status deployment/demo-api --timeout=300s

kubectl apply -k "$ROOT/gitops/platform/istio"

echo
echo "Istio gateway NodePort:"
kubectl -n istio-system get svc istio-ingressgateway
echo
echo "Test command example:"
echo '  NODE_PORT=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath="{.spec.ports[?(@.name==\"http2\")].nodePort}")'
echo '  curl -H "Host: demo-istio.local" "http://127.0.0.1:${NODE_PORT}/version"'

