#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：命令失败、变量未定义、管道失败都会让脚本退出。

# 计算项目根目录：脚本在 scripts/ 下，所以向上一级就是仓库根目录。
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 本地 bare Git 仓库路径；ArgoCD 会通过 git daemon 读取这个 mirror。
MIRROR="${MIRROR:-/Users/yuliang/Documents/mpa/local-gitops-lab-bare.git}"
# git daemon 的 base-path，也就是 mirror 所在目录。
BASE_PATH="$(dirname "$MIRROR")"
# bare 仓库目录名，例如 local-gitops-lab-bare.git。
REPO_NAME="$(basename "$MIRROR")"
# ArgoCD 在 Kubernetes Pod 内访问宿主机 git daemon 的地址。
LOCAL_REPO_URL="${LOCAL_REPO_URL:-git://host.orb.internal/${REPO_NAME}}"

# 如果本地 bare mirror 还不存在，就从当前项目克隆一个 bare 仓库。
if [ ! -d "$MIRROR" ]; then
# 创建 bare Git 仓库；bare 仓库没有工作区，适合给服务端读取。
  git clone --bare "$ROOT" "$MIRROR"
# 如果 bare mirror 已存在，就把当前项目 main 分支强制同步进去。
else
# 从当前工作仓库 fetch main 到 bare mirror 的 main，保证 ArgoCD 能看到最新 commit。
  git --git-dir="$MIRROR" fetch "$ROOT" main:main --force
# 结束 mirror 是否存在的判断。
fi

# 创建 git-daemon-export-ok 文件，允许 git daemon 导出这个仓库。
touch "$MIRROR/git-daemon-export-ok"

# 检查本机 127.0.0.1 上是否已经有 git daemon 能访问这个 mirror。
if git ls-remote "git://127.0.0.1/${REPO_NAME}" refs/heads/main >/dev/null 2>&1; then
# 如果能访问，说明 git daemon 已经在运行，不需要重复启动。
  echo "git daemon is already serving ${REPO_NAME}"
# 如果访问失败，就启动一个新的 git daemon。
else
# 后台启动 git daemon，把日志写到 .git/git-daemon.log。
  nohup git daemon --verbose --export-all --base-path="$BASE_PATH" --reuseaddr "$BASE_PATH" > "$ROOT/.git/git-daemon.log" 2>&1 &
# 记录后台 git daemon 的 PID，方便人工排查或停止。
  echo $! > "$ROOT/.git/git-daemon.pid"
# 等待 2 秒，给 git daemon 完成监听端口的时间。
  sleep 2
# 结束 git daemon 是否已运行的判断。
fi

# 打印 mirror 的 main 分支 commit，用来确认 git daemon 能读到仓库。
git ls-remote "git://127.0.0.1/${REPO_NAME}" refs/heads/main

# 这些是本地实验里需要从 Git mirror 拉取的 ArgoCD Application。
# 如果某个 Application 还没有创建，下面循环会跳过它。
APPLICATIONS=(
  demo-api
  demo-api-canary
  user-service
  order-api
  order-api-canary
)

# 逐个把已存在的 Application repoURL 改成本地 git mirror，并触发 hard refresh。
for app in "${APPLICATIONS[@]}"; do
  # 只有 Application 已经存在时才 patch，避免第一次安装前脚本报错。
  if kubectl -n argocd get application "$app" >/dev/null 2>&1; then
    # 把 Application 的 repoURL 临时改成本地 git mirror。
    kubectl -n argocd patch application "$app" --type merge -p "{\"spec\":{\"source\":{\"repoURL\":\"${LOCAL_REPO_URL}\"}}}"
    # hard refresh，让 ArgoCD 立刻重新拉取 manifests。
    kubectl -n argocd annotate application "$app" argocd.argoproj.io/refresh=hard --overwrite
  fi
done

# 输出 Application 当前 repoURL、同步状态和健康状态：
# 自定义输出列，方便快速确认 ArgoCD 是否使用了本地 mirror，以及是否 Synced。
kubectl -n argocd get applications "${APPLICATIONS[@]}" --ignore-not-found \
  -o custom-columns=NAME:.metadata.name,REPO:.spec.source.repoURL,SYNC:.status.sync.status,HEALTH:.status.health.status
