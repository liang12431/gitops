#!/usr/bin/env bash
set -euo pipefail

echo "== tools =="
for c in kubectl helm docker git jq; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '%s: %s\n' "$c" "$(command -v "$c")"
  else
    printf '%s: MISSING\n' "$c"
  fi
done

echo
echo "== kubectl context =="
kubectl config current-context

echo
echo "== nodes =="
kubectl get nodes -o wide

