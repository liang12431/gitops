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

### 12. Flagger 安装和初始化成功

执行命令：

```bash
./scripts/07-install-flagger.sh
```

安装组件：

```text
flagger
flagger-loadtester
```

创建 ArgoCD Application：

```text
demo-api-canary
```

验证命令：

```bash
kubectl -n flagger-system get pods
kubectl -n argocd get application demo-api-canary
kubectl -n demo get canary demo-api
kubectl -n demo get deploy,svc,virtualservice,destinationrule | grep demo-api
```

结果：

```text
flagger Ready
flagger-loadtester Ready
demo-api-canary ArgoCD Sync=Synced
Canary demo-api phase=Initialized
```

Flagger 生成/管理的资源：

```text
deployment/demo-api-primary
service/demo-api
service/demo-api-primary
service/demo-api-canary
virtualservice/demo-api
destinationrule/demo-api-primary
destinationrule/demo-api-canary
```

说明：

```text
之前手动创建的 VirtualService/demo-api 只是 Istio baseline 测试用。
安装 Flagger 后已删除，后续由 Flagger 接管 demo-api 的 VirtualService。

### 13. 第一次 app-a -> app-b 灰度自动完成

执行操作：

```text
GitOps 中把 demo-api 镜像从 app-a:0.1.1 改为 app-b:0.1.1。
ArgoCD 同步 Deployment。
Flagger 检测到新版本并启动 canary。
```

观察结果：

```text
demo-api Deployment = app-b:0.1.1
demo-api-primary Deployment = app-a:0.1.1
Canary phase 从 Initialized -> Progressing -> Promoting -> Finalising -> Succeeded
```

问题：

```text
当前 canary.yaml 没有 confirm-promotion webhook gate。
iterations=1，Flagger 很快自动 promotion。
最终 primary 也变成 app-b。
```

现象：

```text
普通请求和 x-canary:true 请求最终都返回 app-b。
```

结论：

```text
如果要稳定演示“普通请求 app-a，带 header 请求 app-b”，需要加入 promotion gate，
让 Flagger 停在 WaitingPromotion，而不是立刻把 app-b 提升为 primary。
```

### 14. gate-service 镜像拉取问题

执行命令：

```bash
./scripts/08-install-gate-service.sh
```

遇到的问题：

```text
gate-service 初版使用 python:3.12-alpine。
Pod 卡在 ImagePullBackOff。
事件显示 Docker Hub EOF。
```

解决方案：

```text
不用外部 Python 镜像。
改成本地 Java HTTP server。
使用本地 javac/jar 构建 gate-service.jar。
使用已经验证可拉取的 amazoncorretto:21-alpine 作为运行镜像。
推送到 localhost:5001/demo/gate-service:0.1.1。
额外注意：Pod 内 BusyBox wget 不支持 --method=PUT，因此 gate-service 同时支持：
POST /gate/promotion/open
POST /gate/rollback/open
这样可以用 wget --post-data '' 触发 gate。
```

执行成功后的验证：

```bash
./scripts/01-build-push-images.sh
kubectl apply -k gitops/platform/gate-service
kubectl -n demo rollout status deployment/gate-service --timeout=300s
kubectl -n demo exec deploy/gate-service -- wget -qO- http://127.0.0.1:8080/
```

结果：

```text
gate-service
```

### 15. ArgoCD 在 Pod 内访问 GitHub EOF

执行 ArgoCD hard refresh 后，两个 Application 一直是：

```text
Sync = Unknown
Health = Healthy
```

ArgoCD repo-server 报错：

```text
failed to list refs:
Get "https://github.com/liang12431/gitops.git/info/refs?service=git-upload-pack": EOF
```

诊断命令：

```bash
curl -I --max-time 20 \
  'https://github.com/liang12431/gitops.git/info/refs?service=git-upload-pack'

kubectl -n demo exec deploy/gate-service -- \
  wget -S -O- --timeout=20 \
  'https://github.com/liang12431/gitops.git/info/refs?service=git-upload-pack'

kubectl -n argocd logs deploy/argocd-repo-server --tail=80
```

结论：

```text
宿主机可以访问 GitHub。
Kubernetes Pod 内访问 GitHub TLS 被 reset。
所以这不是 GitOps YAML 错误，而是本地 OrbStack/K8s Pod 到 GitHub 的网络问题。
```

本地解决方案：

```text
GitHub 仍然作为远端代码仓库。
为了让 ArgoCD 在本地实验继续跑通，宿主机启动一个只读 git daemon mirror。
ArgoCD Application 临时改用：
git://host.orb.internal/local-gitops-lab-bare.git
```

执行命令：

```bash
./scripts/09-use-local-git-mirror.sh
```

结果：

```text
demo-api          git://host.orb.internal/local-gitops-lab-bare.git   Synced
demo-api-canary   git://host.orb.internal/local-gitops-lab-bare.git   Synced
```

注意：

```text
每次本地 commit 后，如果希望 ArgoCD 从本地 mirror 看到最新内容，需要再次执行：
./scripts/09-use-local-git-mirror.sh
```

### 16. 恢复 primary 到 app-a

由于第一次自动 promotion 已经把 primary 提升到了 app-b，所以先把 GitOps 目标镜像恢复为 app-a。

然后打开 promotion gate：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' http://127.0.0.1:8080/gate/promotion/open
```

等待 Flagger：

```bash
kubectl -n demo get canary demo-api -o wide
kubectl -n demo get deploy demo-api demo-api-primary \
  -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas
```

结果：

```text
demo-api phase = Succeeded
demo-api-primary image = localhost:5001/demo/app-a:0.1.1
```

请求验证：

```bash
PORT=$(kubectl -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

curl -s -H 'Host: demo-istio.local' http://127.0.0.1:${PORT}/version
curl -s -H 'Host: demo-istio.local' -H 'x-canary: true' http://127.0.0.1:${PORT}/version
```

结果：

```json
{"app":"app-a","version":"v1"}
{"app":"app-a","version":"v1"}
```

### 17. 最终 header 灰度：普通请求 app-a，带 header 请求 app-b

修改 GitOps：

```yaml
images:
  - name: localhost:5001/demo/app-a
    newName: localhost:5001/demo/app-b
    newTag: 0.1.1
```

提交并推送：

```bash
git add gitops/applications/demo-api/overlays/local/kustomization.yaml
git commit -m "Support local promotion gate commands"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

ArgoCD 同步后：

```text
deployment/demo-api         = localhost:5001/demo/app-b:0.1.1
deployment/demo-api-primary = localhost:5001/demo/app-a:0.1.1
```

等待 Flagger：

```bash
kubectl -n demo get canary demo-api -o wide
kubectl -n demo describe canary demo-api
```

结果：

```text
demo-api phase = WaitingPromotion
Halt demo-api.demo advancement waiting for promotion approval check promotion confirmation status
```

此时没有打开 promotion gate，因此 Flagger 停在 WaitingPromotion。

请求验证：

```bash
curl -s -H 'Host: demo-istio.local' http://127.0.0.1:${PORT}/version
curl -s -H 'Host: demo-istio.local' -H 'x-canary: true' http://127.0.0.1:${PORT}/version
```

结果：

```json
{"app":"app-a","version":"v1"}
{"app":"app-b","version":"v2"}
```

这说明：

```text
普通请求 -> Istio Gateway -> VirtualService -> demo-api-primary -> app-a
带 x-canary:true 请求 -> Istio Gateway -> VirtualService header match -> demo-api-canary -> app-b
Flagger 负责生成/更新 VirtualService 和 DestinationRule。
Istio/Envoy 负责真正按请求头转发流量。
```

### 18. ArgoCD 与 Flagger 同时管理 Service 的 diff

最终等待 promotion 时，ArgoCD `demo-api` 曾显示：

```text
demo-api OutOfSync
```

检查资源后发现只有：

```text
Service/demo-api sync=OutOfSync
```

原因：

```text
最初 NGINX baseline 阶段，Service/demo-api 由 demo-api Application 创建。
安装 Flagger 后，Flagger 会接管 Service/demo-api。
Flagger 把 selector 改成 app=demo-api-primary。
Flagger 把 targetPort 从命名端口 http 解析成 8080。
因此 live Service 和 GitOps 里最初的 Service manifest 有 diff。
```

修复：

```yaml
spec:
  syncPolicy:
    syncOptions:
      - RespectIgnoreDifferences=true
  ignoreDifferences:
    - group: ""
      kind: Service
      name: demo-api
      namespace: demo
      jsonPointers:
        - /spec/selector
        - /spec/ports
```

执行 live patch：

```bash
kubectl -n argocd patch application demo-api --type merge -p '{
  "spec": {
    "syncPolicy": {
      "syncOptions": [
        "CreateNamespace=true",
        "RespectIgnoreDifferences=true"
      ]
    },
    "ignoreDifferences": [
      {
        "group": "",
        "kind": "Service",
        "name": "demo-api",
        "namespace": "demo",
        "jsonPointers": [
          "/spec/selector",
          "/spec/ports"
        ]
      }
    ]
  }
}'
```

结果：

```text
demo-api Synced Healthy
Service/demo-api sync=Synced
Deployment/demo-api sync=Synced
Ingress/demo-api sync=Synced
```

如果后续要把 app-b 提升为 primary：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' http://127.0.0.1:8080/gate/promotion/open
```
```
