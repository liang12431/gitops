#!/usr/bin/env bash
# 使用当前环境里的 bash 来执行这个脚本，避免不同机器 bash 路径不一致。
set -euo pipefail
# 开启严格模式：
# -e：任意命令失败就退出，避免继续执行错误流程。
# -u：使用未定义变量时报错，避免拼错变量名。
# -o pipefail：管道中任意一步失败，整个管道都算失败。

# 打印一个分组标题，表示下面开始检查本机工具。
echo "== tools =="
# 依次检查这些本地命令是否存在。
for c in kubectl helm docker git jq; do
# 如果 command -v 能找到命令路径，说明这个工具已安装。
  if command -v "$c" >/dev/null 2>&1; then
# 打印工具名和它在本机上的实际路径。
    printf '%s: %s\n' "$c" "$(command -v "$c")"
# 如果找不到命令路径，说明这个工具缺失。
  else
# 打印 MISSING，提醒后续脚本可能不能正常运行。
    printf '%s: MISSING\n' "$c"
# 结束 if 判断。
  fi
# 结束工具检查循环。
done

# 打印空行，让输出更容易阅读。
echo
# 打印当前 kubectl context 分组标题。
echo "== kubectl context =="
# 输出当前 kubectl 正在操作的 Kubernetes 集群上下文。
kubectl config current-context

# 打印空行，让输出更容易阅读。
echo
# 打印 Kubernetes 节点分组标题。
echo "== nodes =="
# 查看当前集群节点的详细信息，用来确认 OrbStack Kubernetes 是否 Ready。
kubectl get nodes -o wide
