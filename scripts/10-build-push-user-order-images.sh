#!/usr/bin/env bash
# 构建并推送 user-service、order-service-v1、order-service-v2 镜像。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 本地镜像仓库地址，默认 localhost:5001。
REGISTRY="${REGISTRY:-localhost:5001}"
# user/order 链路的镜像版本，默认 0.1.0。
VERSION="${VERSION:-0.1.0}"

# 确保本地 Docker registry 正在运行。
if ! docker ps --format '{{.Names}}' | grep -qx local-registry; then
  if docker ps -a --format '{{.Names}}' | grep -qx local-registry; then
    docker start local-registry >/dev/null
  else
    docker run -d --restart=always -p 5001:5000 --name local-registry registry:2 >/dev/null
  fi
fi

# 构建 user-service jar。
(
  cd "$ROOT/apps/user-service"
  mvn -q -DskipTests package
)

# 构建 order-service v1 jar。
(
  cd "$ROOT/apps/order-service-v1"
  mvn -q -DskipTests package
)

# 构建 order-service v2 jar。
(
  cd "$ROOT/apps/order-service-v2"
  mvn -q -DskipTests package
)

# 构建 user-service 镜像；plain 输出在本地终端里更稳定，也更方便排查卡点。
docker build --progress=plain -t "$REGISTRY/demo/user-service:$VERSION" "$ROOT/apps/user-service"
# 构建 order-service v1 镜像；plain 输出在本地终端里更稳定，也更方便排查卡点。
docker build --progress=plain -t "$REGISTRY/demo/order-service-v1:$VERSION" "$ROOT/apps/order-service-v1"
# 构建 order-service v2 镜像；plain 输出在本地终端里更稳定，也更方便排查卡点。
docker build --progress=plain -t "$REGISTRY/demo/order-service-v2:$VERSION" "$ROOT/apps/order-service-v2"

# 推送 user-service 镜像。
docker push "$REGISTRY/demo/user-service:$VERSION"
# 推送 order-service v1 镜像。
docker push "$REGISTRY/demo/order-service-v1:$VERSION"
# 推送 order-service v2 镜像。
docker push "$REGISTRY/demo/order-service-v2:$VERSION"

# 输出构建结果。
echo "User/order images pushed to $REGISTRY with tag $VERSION"
