# 执行记录

## 2026-06-29

### 1. 前置检查

执行命令：

```bash
for c in kubectl helm docker git istioctl argocd jq; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '%s: %s\n' "$c" "$(command -v "$c")"
  else
    printf '%s: MISSING\n' "$c"
  fi
done

kubectl config current-context
kubectl get nodes -o wide
kubectl get ns
docker version
helm version --short
```

结果：

```text
kubectl: /opt/homebrew/bin/kubectl
helm: /opt/homebrew/bin/helm
docker: /usr/local/bin/docker
git: /usr/bin/git
jq: /opt/homebrew/anaconda3/bin/jq
istioctl: MISSING
argocd: MISSING

kubectl context: orbstack
node: orbstack Ready
Kubernetes version: v1.34.8+orb1
Docker server: 29.4.0
Helm: v4.1.3
```

结论：

```text
OrbStack Kubernetes 可用。
kubectl/helm/docker/git 可用。
istioctl 和 argocd CLI 暂时没有安装。
```

处理方案：

```text
Istio 优先尝试 Helm 安装；如果 Helm 方式遇到问题，再安装 istioctl。
ArgoCD 优先用 kubectl/Helm 和 UI；argocd CLI 不是第一阶段必需。
```

### 2. Git 仓库准备

目标仓库：

```text
git@github.com:liang12431/gitops.git
```

执行命令：

```bash
cd /Users/yuliang/Documents/mpa
git clone git@github.com:liang12431/gitops.git local-gitops-lab
cd local-gitops-lab
git status --short --branch
git remote -v
```

结果：

```text
仓库克隆成功。
远端仓库当前为空仓库。
本地目录：/Users/yuliang/Documents/mpa/local-gitops-lab
```

### 3. 创建实验仓库骨架

已创建：

```text
apps/app-a
apps/app-b
gitops/applications/demo-api
gitops/applications/demo-api-canary
gitops/argocd-apps
scripts
```

遇到的问题：

```text
kubectl kustomize gitops/applications/demo-api/overlays/local
```

最初在 overlay 中引用了：

```text
../../../../platform/namespaces/demo.yaml
```

Kustomize 报错：

```text
security; file .../gitops/platform/namespaces/demo.yaml is not in or below ...
```

原因：

```text
kubectl 内置 kustomize 默认有 load restrictor，不能从 overlay 目录引用目录外部文件。
```

解决方案：

```text
应用 overlay 只保留 Deployment/Service/Ingress。
namespace 单独通过 gitops/platform/namespaces/demo.yaml apply。
ArgoCD Application 使用 CreateNamespace=true。
```

### 4. Docker 基础镜像拉取问题

执行命令：

```bash
./scripts/01-build-push-images.sh
```

遇到的问题：

```text
Docker 拉取 maven:3.9.9-eclipse-temurin-21 和 eclipse-temurin:21-jre 失败。
错误来自当前 Docker registry mirror:
https://docker.m.daocloud.io
返回 401 Unauthorized。
```

排查命令：

```bash
docker info
docker pull amazoncorretto:21-alpine
```

结果：

```text
amazoncorretto:21-alpine 可以正常拉取。
本机已经安装 Java 和 Maven。
```

解决方案：

```text
不再使用 Docker 多阶段 Maven builder。
改成本机 mvn package 生成 jar。
Dockerfile 只负责把 jar 放进 amazoncorretto:21-alpine 运行镜像。
```

### 5. NGINX Ingress 安装卡在 admission job

执行命令：

```bash
./scripts/02-install-nginx-baseline.sh
```

遇到的问题：

```text
Helm release ingress-nginx 长时间处于 pending-install。
Pod ingress-nginx-admission-create 卡在 ContainerCreating/Pulling。
镜像：registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9
```

排查命令：

```bash
kubectl -n ingress-nginx get all
kubectl -n ingress-nginx get events --sort-by=.lastTimestamp | tail -30
helm -n ingress-nginx list
```

解决方案：

```bash
docker pull registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.9
helm -n ingress-nginx uninstall ingress-nginx || true
kubectl delete job -n ingress-nginx ingress-nginx-admission-create ingress-nginx-admission-patch --ignore-not-found=true
./scripts/02-install-nginx-baseline.sh
```

后续又遇到：

```text
创建 Ingress 时 admission webhook 报 no endpoints available。
```

原因：

```text
ingress-nginx-controller Deployment 还没 Ready，admission service 暂时没有 endpoints。
```

解决方案：

```text
在脚本里增加：
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s
等待 controller Ready 后再 apply Ingress。
```

### 6. K8s + NGINX baseline 验证成功

执行命令：

```bash
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=360s
kubectl apply -f gitops/platform/namespaces/demo.yaml
kubectl apply -k gitops/applications/demo-api/overlays/local
kubectl -n demo rollout status deployment/demo-api --timeout=240s
./scripts/03-smoke-nginx.sh
```

验证结果：

```text
Service port-forward 返回 app-a v1。
Ingress Host demo.local 返回 app-a v1。
```

实际响应示例：

```json
{"app":"app-a","version":"v1"}
```

当前资源状态：

```text
deployment/demo-api Ready 1/1
service/demo-api ClusterIP 8080
ingress/demo-api host demo.local
ingress-nginx-controller LoadBalancer 192.168.139.2
```

### 7. Observability kustomize namespace 路径问题

执行命令：

```bash
./scripts/04-install-observability.sh
```

遇到的问题：

```text
gitops/platform/observability/kustomization.yaml 引用了 ../namespaces/observability.yaml。
kubectl kustomize 因 load restrictor 拒绝读取上层目录文件。
```

解决方案：

```text
和 demo namespace 一样，namespace 单独 apply：
kubectl apply -f gitops/platform/namespaces/observability.yaml

observability kustomization 只保留 OTel Collector、Prometheus、Grafana 组件。
```

### 8. Observability 安装和验证成功

执行命令：

```bash
./scripts/01-build-push-images.sh
./scripts/04-install-observability.sh
kubectl apply -k gitops/applications/demo-api/overlays/local
kubectl -n demo rollout status deployment/demo-api --timeout=240s
./scripts/03-smoke-nginx.sh
```

安装组件：

```text
OpenTelemetry Collector
Prometheus
Grafana
```

验证 Prometheus targets：

```bash
kubectl -n observability port-forward svc/prometheus 19090:9090
curl -s 'http://127.0.0.1:19090/api/v1/targets' | jq
```

结果：

```text
demo-api-actuator = up
otel-collector = up
```

验证 Prometheus 查询：

```bash
curl -s --get 'http://127.0.0.1:19090/api/v1/query' \
  --data-urlencode 'query=up{job="demo-api-actuator"}'
```

结果：

```text
up{job="demo-api-actuator"} = 1
```

验证 OTLP：

```bash
kubectl -n observability logs deploy/otel-collector --tail=30
```

结果：

```text
OTel Collector debug exporter 已收到 TracesExporter spans。
```

访问方式：

```bash
kubectl -n observability port-forward svc/prometheus 9090:9090
kubectl -n observability port-forward svc/grafana 3000:3000
```

Grafana 登录：

```text
admin / admin
```

### 9. ArgoCD Helm repo update 遇到无关 Istio repo 网络问题

执行命令：

```bash
./scripts/05-install-argocd.sh
```

遇到的问题：

```text
helm repo update 会更新所有 repo。
已有 istio repo https://istio-release.storage.googleapis.com/charts 出现 connection reset by peer。
导致 ArgoCD 安装脚本提前失败。
```

解决方案：

```text
把脚本里的 helm repo update 改成只更新 argo repo：
helm repo update argo
```

### 10. ArgoCD 安装和同步验证成功

执行命令：

```bash
./scripts/05-install-argocd.sh
```

第一次下载 chart 时遇到 GitHub release timeout，重试后成功。

验证命令：

```bash
kubectl -n argocd get pods
kubectl -n argocd describe application demo-api
```

结果：

```text
argocd-server Ready
argocd-repo-server Ready
argocd-application-controller Ready
Application demo-api Sync=Synced Health=Healthy
Revision=08c9d5d3814b6dd5ee2a494b4d8cef641c8effea
```

ArgoCD 已经接管：

```text
Service/demo-api
Deployment/demo-api
Ingress/demo-api
```

### 11. Istio 安装和访问验证成功

执行命令：

```bash
./scripts/06-install-istio.sh
```

安装组件：

```text
istio-base
istiod
istio-ingressgateway
```

本地处理：

```text
istio-ingressgateway 使用 NodePort，避免和 ingress-nginx 的 LoadBalancer 80/443 冲突。
```

验证命令：

```bash
kubectl -n istio-system get svc istio-ingressgateway
kubectl -n demo get gateway,virtualservice
NODE_PORT=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
curl -H "Host: demo-istio.local" "http://127.0.0.1:${NODE_PORT}/version"
```

结果：

```json
{"app":"app-a","version":"v1"}
```

注意事项：

```text
kubectl -n demo get pod -o jsonpath='{.spec.containers[*].name}'
```

只显示 `app`，但 Pod annotation 里有：

```text
sidecar.istio.io/status
```

并且 `.spec.initContainers` 里出现：

```text
istio-init
istio-proxy
```

这是当前 Istio/Kubernetes 组合下使用 restartable init container 形式注入 sidecar 的表现，不是没有注入。
