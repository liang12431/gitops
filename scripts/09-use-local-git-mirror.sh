#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR="${MIRROR:-/Users/yuliang/Documents/mpa/local-gitops-lab-bare.git}"
BASE_PATH="$(dirname "$MIRROR")"
REPO_NAME="$(basename "$MIRROR")"
LOCAL_REPO_URL="${LOCAL_REPO_URL:-git://host.orb.internal/${REPO_NAME}}"

if [ ! -d "$MIRROR" ]; then
  git clone --bare "$ROOT" "$MIRROR"
else
  git --git-dir="$MIRROR" fetch "$ROOT" main:main --force
fi

touch "$MIRROR/git-daemon-export-ok"

if git ls-remote "git://127.0.0.1/${REPO_NAME}" refs/heads/main >/dev/null 2>&1; then
  echo "git daemon is already serving ${REPO_NAME}"
else
  nohup git daemon --verbose --export-all --base-path="$BASE_PATH" --reuseaddr "$BASE_PATH" > "$ROOT/.git/git-daemon.log" 2>&1 &
  echo $! > "$ROOT/.git/git-daemon.pid"
  sleep 2
fi

git ls-remote "git://127.0.0.1/${REPO_NAME}" refs/heads/main

kubectl -n argocd patch application demo-api --type merge -p "{\"spec\":{\"source\":{\"repoURL\":\"${LOCAL_REPO_URL}\"}}}"
kubectl -n argocd patch application demo-api-canary --type merge -p "{\"spec\":{\"source\":{\"repoURL\":\"${LOCAL_REPO_URL}\"}}}"
kubectl -n argocd annotate application demo-api argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd annotate application demo-api-canary argocd.argoproj.io/refresh=hard --overwrite

kubectl -n argocd get applications demo-api demo-api-canary \
  -o custom-columns=NAME:.metadata.name,REPO:.spec.source.repoURL,SYNC:.status.sync.status,HEALTH:.status.health.status

