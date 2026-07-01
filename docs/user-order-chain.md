# User -> Order 全链路操作说明

更新时间：2026-07-01

本文档说明新增的 `user-service -> order-api` 链路。这个链路用于学习：

```text
外部请求
  -> Istio Gateway
  -> user-service
  -> user-service sidecar Envoy
  -> order-api primary/canary
```

同时演示：

```text
/user/1 -> user-service 访问 www.baidu.com
/user/2 -> user-service 正常调用 order-api primary，返回 order v1
/user/3 -> user-service 带 x-order-canary:true 调用 order-api canary，返回 order v2
```

## 1. 当前状态

当前已经部署完成：

```text
user-service       普通 ArgoCD 部署，不走 Flagger
order-api          ArgoCD 部署，受 Flagger 监听
order-api-canary   ArgoCD 管理 Canary CR，Flagger 根据它生成 primary/canary
```

当前版本：

```text
order-api-primary = order-service-v1:0.1.0
order-api         = order-service-v2:0.1.0
Flagger phase     = WaitingPromotion
```

所以当前结果是：

```text
user/2 -> order primary -> v1
user/3 -> order canary  -> v2
```

## 2. 新增目录

应用代码：

```text
apps/user-service
apps/order-service-v1
apps/order-service-v2
```

GitOps 应用：

```text
gitops/applications/user-service
gitops/applications/order-api
gitops/applications/order-api-canary
```

ArgoCD Application：

```text
gitops/argocd-apps/user-service-application.yaml
gitops/argocd-apps/order-api-application.yaml
gitops/argocd-apps/order-api-canary-application.yaml
```

脚本：

```text
scripts/10-build-push-user-order-images.sh
scripts/11-install-user-order-chain.sh
```

## 3. 组件关系

```text
user-service
  - Deployment/user-service
  - Service/user-service
  - VirtualService/user-service
  - Gateway/user-order-gateway
  - ServiceEntry/baidu-external

order-api
  - Deployment/order-api
  - Service/order-api
  - Canary/order-api
  - Flagger 自动生成 Deployment/order-api-primary
  - Flagger 自动生成 Service/order-api-primary
  - Flagger 自动生成 Service/order-api-canary
  - Flagger 自动生成 VirtualService/order-api
```

## 4. 流量路径

### 4.1 `/user/1`

```text
curl Host=user.local /user/1
  -> istio-ingressgateway
  -> Gateway/user-order-gateway
  -> VirtualService/user-service
  -> Service/user-service
  -> user-service Pod
  -> user-service 访问 http://www.baidu.com
  -> 返回百度响应摘要
```

### 4.2 `/user/2`

```text
curl Host=user.local /user/2
  -> istio-ingressgateway
  -> user-service
  -> HTTP GET http://order-api:8080/orders/2
  -> user-service sidecar 匹配 VirtualService/order-api
  -> 没有 x-order-canary header
  -> Service/order-api-primary
  -> order-service-v1
```

### 4.3 `/user/3`

```text
curl Host=user.local /user/3
  -> istio-ingressgateway
  -> user-service
  -> HTTP GET http://order-api:8080/orders/3
     header: x-order-canary:true
  -> user-service sidecar 匹配 VirtualService/order-api
  -> 命中 x-order-canary:true
  -> Service/order-api-canary
  -> order-service-v2
```

## 5. 当前访问命令

获取 Istio Gateway NodePort：

```bash
NODE_PORT=$(kubectl -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
```

访问百度链路：

```bash
curl -s -H 'Host: user.local' \
  "http://127.0.0.1:${NODE_PORT}/user/1"
```

期望重点：

```json
{
  "route": "baidu",
  "target": "http://www.baidu.com",
  "downstreamStatus": 200
}
```

访问 order primary：

```bash
curl -s -H 'Host: user.local' \
  "http://127.0.0.1:${NODE_PORT}/user/2"
```

期望重点：

```json
{
  "route": "order-primary",
  "orderResponse": "...\"version\":\"v1\"..."
}
```

访问 order canary：

```bash
curl -s -H 'Host: user.local' \
  "http://127.0.0.1:${NODE_PORT}/user/3"
```

期望重点：

```json
{
  "route": "order-canary",
  "sentHeader": "x-order-canary:true",
  "orderResponse": "...\"version\":\"v2\"..."
}
```

直接访问 order canary：

```bash
curl -s -H 'Host: order.local' \
  -H 'x-order-canary: true' \
  "http://127.0.0.1:${NODE_PORT}/orders/3"
```

期望重点：

```json
{
  "service": "order-service",
  "track": "canary",
  "version": "v2"
}
```

## 6. 从零部署 user/order 链路

构建并推送镜像：

```bash
VERSION=0.1.0 ./scripts/10-build-push-user-order-images.sh
```

提交 Git 后同步本地 mirror：

```bash
git push origin main
./scripts/09-use-local-git-mirror.sh
```

创建 ArgoCD Applications：

```bash
./scripts/11-install-user-order-chain.sh
```

检查：

```bash
kubectl -n argocd get applications user-service order-api order-api-canary
kubectl -n demo get deploy,svc,canary | grep -E 'user-service|order-api'
```

## 7. 触发 order canary

初始 `order-api` 是 v1：

```yaml
images:
  - name: localhost:5001/demo/order-service-v1
    newTag: 0.1.0
```

触发 canary 时，把 `gitops/applications/order-api/overlays/local/kustomization.yaml` 改成：

```yaml
images:
  - name: localhost:5001/demo/order-service-v1
    newName: localhost:5001/demo/order-service-v2
    newTag: 0.1.0
```

提交并同步：

```bash
git add gitops/applications/order-api/overlays/local/kustomization.yaml
git commit -m "Roll order API canary to v2"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

等待：

```bash
kubectl -n demo get canary order-api -w
```

期望：

```text
WaitingPromotion
```

## 8. Promotion / rollback

放行 order canary promotion：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/promotion/open
```

触发 rollback：

```bash
kubectl -n demo exec deploy/gate-service -- \
  wget -qO- --post-data '' \
  http://127.0.0.1:8080/gate/rollback/open
```

观察：

```bash
kubectl -n demo describe canary order-api
kubectl -n demo get canary order-api -w
```

## 9. 改代码后重新发布

### 9.1 改 user-service

修改：

```text
apps/user-service
```

构建新 tag：

```bash
VERSION=0.1.1 ./scripts/10-build-push-user-order-images.sh
```

修改：

```text
gitops/applications/user-service/overlays/local/kustomization.yaml
```

把：

```yaml
newTag: 0.1.0
```

改成：

```yaml
newTag: 0.1.1
```

提交同步：

```bash
git add apps/user-service gitops/applications/user-service/overlays/local/kustomization.yaml
git commit -m "Update user-service to 0.1.1"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

### 9.2 改 order-service-v2

修改：

```text
apps/order-service-v2
```

构建：

```bash
VERSION=0.1.1 ./scripts/10-build-push-user-order-images.sh
```

修改：

```text
gitops/applications/order-api/overlays/local/kustomization.yaml
```

示例：

```yaml
images:
  - name: localhost:5001/demo/order-service-v1
    newName: localhost:5001/demo/order-service-v2
    newTag: 0.1.1
```

提交同步：

```bash
git add apps/order-service-v2 gitops/applications/order-api/overlays/local/kustomization.yaml
git commit -m "Roll order API canary to v2 0.1.1"
git push origin main
./scripts/09-use-local-git-mirror.sh
```

## 10. 常用排查命令

ArgoCD：

```bash
kubectl -n argocd get applications user-service order-api order-api-canary
kubectl -n argocd describe application order-api
```

Flagger：

```bash
kubectl -n demo get canary order-api -o wide
kubectl -n demo describe canary order-api
kubectl -n flagger-system logs deploy/flagger --tail=100
```

Istio：

```bash
kubectl -n demo get gateway user-order-gateway -o yaml
kubectl -n demo get virtualservice user-service -o yaml
kubectl -n demo get virtualservice order-api -o yaml
kubectl -n demo get serviceentry baidu-external -o yaml
```

Pod 和 Service：

```bash
kubectl -n demo get deploy,svc,pod | grep -E 'user-service|order-api'
kubectl -n demo logs deploy/user-service -c app --tail=100
kubectl -n demo logs deploy/order-api -c app --tail=100
kubectl -n demo logs deploy/order-api-primary -c app --tail=100
```

