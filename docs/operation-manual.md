# 本地 GitOps + Istio + Flagger 操作手册

更新时间：2026-06-30

本文档是 `/Users/yuliang/Documents/mpa/local-gitops-lab` 的日常使用手册，覆盖访问地址、账号、测试命令、发布流程、promotion/rollback、改代码后重新部署、排查命令和重装顺序。

## 1. 系统说明

本项目在本地 OrbStack Kubernetes 上模拟一套企业级 GitOps 灰度发布链路：

```text
Spring Boot app-a/app-b
  -> Docker 本地镜像仓库
  -> Kubernetes Deployment/Service
  -> NGINX baseline
  -> ArgoCD GitOps
  -> Istio Gateway/VirtualService/DestinationRule
  -> Flagger Canary
  -> OTLP Collector / Prometheus / Grafana
```

当前模型：

```text
app-a = demo-api v1 / primary
app-b = demo-api v2 / canary
```

当前集群状态：

```text
primary: app-a / v1
canary:  app-b / v2
Flagger: WaitingPromotion
```

也就是：

```text
普通请求 -> app-a
带 x-canary:true 请求 -> app-b
```

## 2. 项目路径和仓库

本地项目目录：

```bash
cd /Users/yuliang/Documents/mpa/local-gitops-lab
```

GitHub 远端仓库：

```text
git@github.com:liang12431/gitops.git
```

当前 ArgoCD 使用的本地 Git mirror：

```text
git://host.orb.internal/local-gitops-lab-bare.git
```

说明：

```text
GitHub 仍然是远端代码仓库。
由于本地 OrbStack Pod 内访问 GitHub HTTPS 曾出现 TLS EOF，ArgoCD 当前使用宿主机本地 git daemon mirror。
每次本地 commit 后，需要执行 ./scripts/09-use-local-git-mirror.sh 把最新 commit 同步给 ArgoCD。
```

## 3. Namespace 规划

| Namespace | 作用 |
| --- | --- |
| `demo` | demo-api、demo-api-primary、demo-api-canary、gate-service |
| `argocd` | ArgoCD |
| `istio-system` | Istio 控制面和 Ingress Gateway |
| `flagger-system` | Flagger Controller 和 loadtester |
| `observability` | OTel Collector、Prometheus、Grafana |
| `ingress-nginx` | NGINX baseline |

查看所有 namespace：

```bash
kubectl get ns
```

## 4. 服务访问地址和账号

### 4.1 访问地址总表

| 服务 | 本机访问方式 | 地址 | 账号 | 密码 |
| --- | --- | --- | --- | --- |
| demo-api / Istio 灰度入口 | NodePort | `http://127.0.0.1:31635`，需要 `Host: demo-istio.local` | 无 | 无 |
| demo-api / NGINX baseline | NodePort | `http://127.0.0.1:30981`，需要 `Host: demo.local` | 无 | 无 |
| ArgoCD UI | port-forward | `http://127.0.0.1:8081` | `admin` | 用命令读取，不写入仓库 |
| Grafana | port-forward | `http://127.0.0.1:3000` | `admin` | `admin` |
| Prometheus | port-forward | `http://127.0.0.1:9090` | 无 | 无 |
| gate-service | 集群内服务 | `http://gate-service.demo:8080` | 无 | 无 |
| 本地镜像仓库 | 本机 | `localhost:5001` | 无 | 无 |

不要把 ArgoCD 初始密码提交到 Git 仓库。查看当前本机密码：

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 4.2 动态查看端口

Istio HTTP NodePort：

```bash
kubectl -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}'; echo
```

NGINX HTTP NodePort：

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}'; echo
```

## 5. 打开 Web UI

### 5.1 ArgoCD

启动端口转发：

```bash
kubectl -n argocd port-forward svc/argocd-server 8081:80
```

浏览器打开：

```text
http://127.0.0.1:8081
```

账号：

```text
username: admin
password: 使用 kubectl 读取
```

读取密码：

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

当前应该看到两个 Application：

```text
demo-api
demo-api-canary
```

### 5.2 Grafana

启动端口转发：

```bash
kubectl -n observability port-forward svc/grafana 3000:3000
```

浏览器打开：

```text
http://127.0.0.1:3000
```

账号：

```text
username: admin
password: admin
```

Grafana 已预置 Prometheus 数据源：

```text
http://prometheus.observability.svc.cluster.local:9090
```

### 5.3 Prometheus

启动端口转发：

```bash
kubectl -n observability port-forward svc/prometheus 9090:9090
```

浏览器打开：

```text
http://127.0.0.1:9090
```

常用查询：

```promql
up{job="demo-api-actuator"}
http_server_requests_seconds_count
jvm_memory_used_bytes
process_cpu_usage
```

## 6. 快速健康检查

### 6.1 Kubernetes 和核心 Pod

```bash
kubectl get nodes
kubectl -n demo get pods,svc,deploy
kubectl -n argocd get applications
kubectl -n demo get canary demo-api -o wide
kubectl -n flagger-system get pods
kubectl -n istio-system get pods,svc
kubectl -n observability get pods
```

期望重点：

```text
demo-api          Synced / Healthy
demo-api-canary   Synced
Canary            WaitingPromotion
demo-api          app-b:0.1.1
demo-api-primary  app-a:0.1.1
```

### 6.2 Istio 灰度路由测试

普通请求：

```bash
curl -s -H 'Host: demo-istio.local' \
  http://127.0.0.1:31635/version
```

期望：

```json
{"app":"app-a","version":"v1"}
```

带 canary header：

```bash
curl -s -H 'Host: demo-istio.local' \
  -H 'x-canary: true' \
  http://127.0.0.1:31635/version
```

期望：

```json
{"app":"app-b","version":"v2"}
```

### 6.3 NGINX baseline 测试

```bash
curl -s -H 'Host: demo.local' \
  http://127.0.0.1:30981/version
```

期望：

```json
{"app":"app-a","version":"v1"}
```

### 6.4 应用 health 测试

```bash
curl -s -H 'Host: demo-istio.local' \
  http://127.0.0.1:31635/actuator/health
```

期望：

```json
{"status":"UP"}
```

### 6.5 应用 Prometheus 指标测试

```bash
curl -s -H 'Host: demo-istio.local' \
  http://127.0.0.1:31635/actuator/prometheus | grep http_server_requests
```

期望能看到：

```text
http_server_requests_seconds_count
http_server_requests_seconds_sum
```

### 6.6 OTel Collector 测试

```bash
kubectl -n observability logs deploy/otel-collector --tail=50
```

期望能看到类似：

```text
TracesExporter
MetricsExporter
```

## 7. ArgoCD 本地 Git mirror 流程

当前 ArgoCD 的 repoURL 是：

```text
git://host.orb.internal/local-gitops-lab-bare.git
```

每次本地有新 commit 后，执行：

```bash
./scripts/09-use-local-git-mirror.sh
```

这个脚本会：

```text
1. 创建或更新 /Users/yuliang/Documents/mpa/local-gitops-lab-bare.git
2. 启动或复用本地 git daemon
3. patch ArgoCD Application repoURL
4. hard refresh demo-api 和 demo-api-canary
```

验证 ArgoCD 状态：

```bash
kubectl -n argocd get applications demo-api demo-api-canary \
  -o custom-columns=NAME:.metadata.name,REPO:.spec.source.repoURL,SYNC:.status.sync.status,HEALTH:.status.health.status
```

期望：

```text
demo-api          Synced
demo-api-canary   Synced
```

## 8. 修改代码后如何重新部署

### 8.1 重要原则

不要复用旧镜像 tag。

当前 Deployment 使用：

```yaml
imagePullPolicy: IfNotPresent
```

如果你复用 `0.1.1`，Kubernetes 可能继续使用节点上已有的旧镜像。推荐每次改代码都升级 tag，例如：

```text
0.1.1 -> 0.1.2 -> 0.1.3
```

### 8.2 修改 app-b，并作为 canary 发布

修改代码：

```text
apps/app-b
```

构建并推送新镜像：

```bash
cd /Users/yuliang/Documents/mpa/local-gitops-lab
VERSION=0.1.2 ./scripts/01-build-push-images.sh
```

修改 GitOps 文件：

```text
gitops/applications/demo-api/overlays/local/kustomization.yaml
```

示例：

```yaml
images:
  - name: localhost:5001/demo/app-a
    newName: localhost:5001/demo/app-b
    newTag: 0.1.2
```

提交并推送：

```bash
git add apps/app-b gitops/applications/demo-api/overlays/local/kustomization.yaml
git commit -m "Roll demo-api canary to app-b 0.1.2"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

观察发布：

```bash
kubectl -n demo get canary demo-api -w
```

测试：

```bash
curl -s -H 'Host: demo-istio.local' \
  http://127.0.0.1:31635/version

curl -s -H 'Host: demo-istio.local' \
  -H 'x-canary: true' \
  http://127.0.0.1:31635/version
```

期望：

```text
普通请求仍然访问 primary
带 x-canary:true 请求访问新的 app-b canary
Flagger 停在 WaitingPromotion，等待手动放行
```

### 8.3 修改 app-a，并把 app-a 重新作为目标版本发布

如果你要让 `demo-api` 回到 app-a，修改：

```text
apps/app-a
```

构建新镜像：

```bash
VERSION=0.1.2 ./scripts/01-build-push-images.sh
```

修改：

```text
gitops/applications/demo-api/overlays/local/kustomization.yaml
```

示例：

```yaml
images:
  - name: localhost:5001/demo/app-a
    newName: localhost:5001/demo/app-a
    newTag: 0.1.2
```

提交并同步：

```bash
git add apps/app-a gitops/applications/demo-api/overlays/local/kustomization.yaml
git commit -m "Roll demo-api back to app-a 0.1.2"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

如果希望把它提升为 primary，需要打开 promotion gate：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/promotion/open
```

### 8.4 修改 gate-service 后重新部署

修改：

```text
apps/gate-service/src/GateService.java
```

构建新 gate-service 镜像：

```bash
GATE_VERSION=0.1.2 ./scripts/01-build-push-images.sh
```

修改：

```text
gitops/platform/gate-service/gate-service.yaml
```

示例：

```yaml
image: localhost:5001/demo/gate-service:0.1.2
```

部署：

```bash
kubectl apply -k gitops/platform/gate-service
kubectl -n demo rollout status deployment/gate-service --timeout=300s
```

提交：

```bash
git add apps/gate-service gitops/platform/gate-service/gate-service.yaml
git commit -m "Update gate-service to 0.1.2"
git push origin main
```

## 9. Promotion / Rollback 操作

### 9.1 当前 gate-service 接口

| 接口 | 作用 |
| --- | --- |
| `POST /gate/promotion/open` | 打开一次 promotion gate |
| `POST /gate/promotion/check` | Flagger 用来检查是否允许 promotion |
| `POST /gate/rollback/open` | 打开一次 rollback gate |
| `POST /gate/rollback/check` | Flagger 用来检查是否触发 rollback |

说明：

```text
gate 是 one-shot 的。
open 后，下一次 check 返回 200 并消费这个状态。
没有 open 时，check 返回 403。
```

### 9.2 放行 promotion

当前如果 Canary 卡在：

```text
WaitingPromotion
```

执行：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/promotion/open
```

观察：

```bash
kubectl -n demo get canary demo-api -w
```

期望流程：

```text
WaitingPromotion -> Promoting -> Finalising -> Succeeded
```

最终：

```text
demo-api-primary 使用新版本镜像
普通请求也访问新版本
```

### 9.3 触发 rollback

执行：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/rollback/open
```

观察：

```bash
kubectl -n demo describe canary demo-api
kubectl -n demo get canary demo-api -w
```

## 10. 修改 Flagger 灰度规则

当前 header match 在：

```text
gitops/applications/demo-api-canary/canary.yaml
```

当前配置：

```yaml
match:
  - headers:
      x-canary:
        exact: "true"
```

例如改成：

```yaml
match:
  - headers:
      x-user-group:
        exact: beta
```

提交并同步：

```bash
git add gitops/applications/demo-api-canary/canary.yaml
git commit -m "Change canary header match"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

测试：

```bash
curl -s -H 'Host: demo-istio.local' \
  -H 'x-user-group: beta' \
  http://127.0.0.1:31635/version
```

## 11. 关键资源说明

### 11.1 Flagger 管理的资源

查看：

```bash
kubectl -n demo get canary,deploy,svc,virtualservice,destinationrule
```

关键资源：

```text
deployment/demo-api          canary Deployment
deployment/demo-api-primary  primary Deployment
service/demo-api             对外稳定 Service，Flagger 会把它指向 primary
service/demo-api-primary     primary Service
service/demo-api-canary      canary Service
virtualservice/demo-api      Istio 路由规则
destinationrule/demo-api-*   Istio upstream subset/host 策略
```

查看 VirtualService：

```bash
kubectl -n demo get virtualservice demo-api -o yaml
```

当前应该能看到：

```text
match headers x-canary exact true -> demo-api-canary weight 100
普通 uri prefix / -> demo-api-primary
```

### 11.2 ArgoCD 与 Flagger 的 Service diff

`Service/demo-api` 最初由 `demo-api` Application 创建，但 Flagger 后续会接管它：

```text
selector: app=demo-api-primary
targetPort: 8080
```

为了避免 ArgoCD 和 Flagger 抢同一个 Service 字段，Application 中配置了：

```yaml
ignoreDifferences:
  - group: ""
    kind: Service
    name: demo-api
    namespace: demo
    jsonPointers:
      - /spec/selector
      - /spec/ports
```

## 12. 从零重装顺序

如果需要重建整套实验环境，按下面顺序执行：

```bash
cd /Users/yuliang/Documents/mpa/local-gitops-lab

./scripts/00-check-prereqs.sh
./scripts/01-build-push-images.sh
./scripts/02-install-nginx-baseline.sh
./scripts/03-smoke-nginx.sh
./scripts/04-install-observability.sh
./scripts/05-install-argocd.sh
./scripts/06-install-istio.sh
./scripts/07-install-flagger.sh
./scripts/08-install-gate-service.sh
./scripts/09-use-local-git-mirror.sh
```

重装后验证：

```bash
kubectl -n argocd get applications
kubectl -n demo get canary demo-api -o wide
curl -s -H 'Host: demo-istio.local' http://127.0.0.1:31635/version
curl -s -H 'Host: demo-istio.local' -H 'x-canary: true' http://127.0.0.1:31635/version
```

## 13. 常用排查命令

### 13.1 ArgoCD

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application demo-api
kubectl -n argocd describe application demo-api-canary
kubectl -n argocd logs deploy/argocd-repo-server --tail=100
kubectl -n argocd logs statefulset/argocd-application-controller --tail=100
```

### 13.2 Flagger

```bash
kubectl -n demo get canary demo-api -o wide
kubectl -n demo describe canary demo-api
kubectl -n flagger-system logs deploy/flagger --tail=100
```

### 13.3 Istio

```bash
kubectl -n istio-system get pods,svc
kubectl -n demo get virtualservice demo-api -o yaml
kubectl -n demo get destinationrule -o yaml
kubectl -n demo get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{" init="}{.spec.initContainers[*].name}{"\n"}{end}'
```

注意：当前 Istio 版本里，`istio-proxy` 可能表现为 restartable initContainer，因此不要只看 `.spec.containers`。

### 13.4 应用日志

```bash
kubectl -n demo logs deploy/demo-api -c app --tail=100
kubectl -n demo logs deploy/demo-api-primary -c app --tail=100
kubectl -n demo logs deploy/gate-service --tail=100
```

### 13.5 Observability

```bash
kubectl -n observability get pods,svc
kubectl -n observability logs deploy/otel-collector --tail=100
kubectl -n observability port-forward svc/prometheus 9090:9090
kubectl -n observability port-forward svc/grafana 3000:3000
```

### 13.6 镜像仓库

```bash
docker ps | grep local-registry
curl http://127.0.0.1:5001/v2/_catalog
curl http://127.0.0.1:5001/v2/demo/app-a/tags/list
curl http://127.0.0.1:5001/v2/demo/app-b/tags/list
curl http://127.0.0.1:5001/v2/demo/gate-service/tags/list
```

## 14. 常见问题

### 14.1 ArgoCD 显示 Unknown，repo-server 报 GitHub EOF

原因：

```text
OrbStack Pod 内访问 GitHub TLS 连接被 reset。
```

解决：

```bash
./scripts/09-use-local-git-mirror.sh
```

### 14.2 ArgoCD 显示 Service/demo-api OutOfSync

原因：

```text
Flagger 接管了 Service/demo-api 的 selector 和 ports。
```

解决：

```text
Application 已配置 ignoreDifferences。
如果仍 OutOfSync，先 hard refresh：
```

```bash
kubectl -n argocd annotate application demo-api \
  argocd.argoproj.io/refresh=hard --overwrite
```

### 14.3 带 header 还是访问 app-a

检查：

```bash
kubectl -n demo get canary demo-api -o wide
kubectl -n demo get virtualservice demo-api -o yaml
kubectl -n demo get deploy demo-api demo-api-primary -o wide
```

常见原因：

```text
1. Flagger 还没进入 WaitingPromotion
2. VirtualService 还没更新 header match
3. 请求没有带 Host: demo-istio.local
4. 请求头不是 x-canary: true
```

正确请求：

```bash
curl -s -H 'Host: demo-istio.local' \
  -H 'x-canary: true' \
  http://127.0.0.1:31635/version
```

### 14.4 改了代码但响应没变

常见原因：

```text
镜像 tag 没变，Kubernetes 复用了旧镜像。
```

解决：

```text
每次改代码都升级 VERSION，并修改 kustomization.yaml 的 newTag。
```

### 14.5 promotion 没有继续

检查：

```bash
kubectl -n demo describe canary demo-api
kubectl -n demo logs deploy/gate-service --tail=100
```

放行：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/promotion/open
```

## 15. 推荐日常工作流

最常用的 app-b canary 发布流程：

```bash
cd /Users/yuliang/Documents/mpa/local-gitops-lab

# 1. 修改 apps/app-b 代码

# 2. 构建新镜像
VERSION=0.1.2 ./scripts/01-build-push-images.sh

# 3. 修改 GitOps tag
vi gitops/applications/demo-api/overlays/local/kustomization.yaml

# 4. 提交
git add apps/app-b gitops/applications/demo-api/overlays/local/kustomization.yaml
git commit -m "Roll demo-api canary to app-b 0.1.2"
git push origin main

# 5. 同步给 ArgoCD
./scripts/09-use-local-git-mirror.sh

# 6. 验证灰度
curl -s -H 'Host: demo-istio.local' http://127.0.0.1:31635/version
curl -s -H 'Host: demo-istio.local' -H 'x-canary: true' http://127.0.0.1:31635/version

# 7. 确认没问题后 promotion
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/promotion/open

# 8. 观察完成
kubectl -n demo get canary demo-api -w
```

