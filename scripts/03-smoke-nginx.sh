#!/usr/bin/env bash
set -euo pipefail

echo "Testing via port-forward to Service first..."
kubectl -n demo port-forward svc/demo-api 18080:8080 >/tmp/demo-api-port-forward.log 2>&1 &
PID=$!
trap 'kill "$PID" >/dev/null 2>&1 || true' EXIT
sleep 3
curl -s http://127.0.0.1:18080/version
echo

echo "Testing via Ingress host demo.local..."
curl -s -H 'Host: demo.local' http://127.0.0.1/version || true
echo

