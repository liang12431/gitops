#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-localhost:5001}"
VERSION="${VERSION:-0.1.1}"

if ! docker ps --format '{{.Names}}' | grep -qx local-registry; then
  if docker ps -a --format '{{.Names}}' | grep -qx local-registry; then
    docker start local-registry >/dev/null
  else
    docker run -d --restart=always -p 5001:5000 --name local-registry registry:2 >/dev/null
  fi
fi

(
  cd "$ROOT/apps/app-a"
  mvn -q -DskipTests package
)
(
  cd "$ROOT/apps/app-b"
  mvn -q -DskipTests package
)

docker build -t "$REGISTRY/demo/app-a:$VERSION" "$ROOT/apps/app-a"
docker build -t "$REGISTRY/demo/app-b:$VERSION" "$ROOT/apps/app-b"

docker push "$REGISTRY/demo/app-a:$VERSION"
docker push "$REGISTRY/demo/app-b:$VERSION"

echo "Images pushed to $REGISTRY with tag $VERSION"
