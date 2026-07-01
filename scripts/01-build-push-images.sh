#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 本地镜像仓库地址，默认使用 localhost:5001；也可以通过环境变量 REGISTRY 覆盖。
REGISTRY="${REGISTRY:-localhost:5001}"
# app-a/app-b 的镜像版本号，默认 0.1.1；也可以执行时用 VERSION=0.1.2 覆盖。
VERSION="${VERSION:-0.1.1}"
# gate-service 的镜像版本号，默认 0.1.1；也可以执行时用 GATE_VERSION=0.1.2 覆盖。
GATE_VERSION="${GATE_VERSION:-0.1.1}"

# 检查名为 local-registry 的 Docker 容器是否正在运行。
if ! docker ps --format '{{.Names}}' | grep -qx local-registry; then
# 如果没在运行，再检查这个容器是否曾经创建过但现在停止了。
  if docker ps -a --format '{{.Names}}' | grep -qx local-registry; then
# 如果容器存在但停止，就直接启动它。
    docker start local-registry >/dev/null
# 如果容器完全不存在，就新建一个 registry:2 容器，并把本机 5001 映射到容器 5000。
  else
# --restart=always 表示 Docker 重启后这个 registry 也会自动启动。
    docker run -d --restart=always -p 5001:5000 --name local-registry registry:2 >/dev/null
# 结束“容器是否存在”的判断。
  fi
# 结束“容器是否正在运行”的判断。
fi

# 用子 shell 进入 app-a 目录，避免影响后面的工作目录。
(
# 切换到 app-a 项目目录。
  cd "$ROOT/apps/app-a"
# 用 Maven 构建 app-a，跳过测试，生成 target/app-a-0.1.0.jar。
  mvn -q -DskipTests package
# 退出子 shell 后会自动回到原目录。
)
# 用子 shell 进入 app-b 目录，避免影响后面的工作目录。
(
# 切换到 app-b 项目目录。
  cd "$ROOT/apps/app-b"
# 用 Maven 构建 app-b，跳过测试，生成 target/app-b-0.1.0.jar。
  mvn -q -DskipTests package
# 退出子 shell 后会自动回到原目录。
)
# 用子 shell 进入 gate-service 目录，避免影响后面的工作目录。
(
# 切换到 gate-service 项目目录。
  cd "$ROOT/apps/gate-service"
# 创建 Java 编译输出目录。
  mkdir -p target/classes
# 用 javac 编译 GateService.java 到 target/classes。
  javac -d target/classes src/GateService.java
# 把编译后的 class 打成可运行 jar，并指定主类 GateService。
  jar --create --file target/gate-service.jar --main-class GateService -C target/classes .
# 退出子 shell 后会自动回到原目录。
)

# 基于 apps/app-a/Dockerfile 构建 app-a 镜像。
docker build -t "$REGISTRY/demo/app-a:$VERSION" "$ROOT/apps/app-a"
# 基于 apps/app-b/Dockerfile 构建 app-b 镜像。
docker build -t "$REGISTRY/demo/app-b:$VERSION" "$ROOT/apps/app-b"
# 基于 apps/gate-service/Dockerfile 构建 gate-service 镜像。
docker build -t "$REGISTRY/demo/gate-service:$GATE_VERSION" "$ROOT/apps/gate-service"

# 把 app-a 镜像推送到本地 registry，Kubernetes 后续从这里拉镜像。
docker push "$REGISTRY/demo/app-a:$VERSION"
# 把 app-b 镜像推送到本地 registry，Kubernetes 后续从这里拉镜像。
docker push "$REGISTRY/demo/app-b:$VERSION"
# 把 gate-service 镜像推送到本地 registry。
docker push "$REGISTRY/demo/gate-service:$GATE_VERSION"

# 输出构建和推送完成提示。
echo "Images pushed to $REGISTRY with tag $VERSION"
