# 本地 GitOps + Istio + Flagger 实验仓库

这个仓库用于在本地 OrbStack Kubernetes 上跑通一套企业级发布流程缩小版：

```text
Spring Boot app-a/app-b
  -> Docker 镜像
  -> Kubernetes
  -> NGINX baseline
  -> ArgoCD GitOps
  -> Istio
  -> Flagger Canary
  -> OTLP / Prometheus / Grafana
```

## 当前目标

先把最小闭环跑通：

```text
app-a -> K8s Deployment/Service -> NGINX Ingress -> curl demo.local/version
```

然后逐步引入：

```text
Observability -> ArgoCD -> Istio -> Flagger -> app-a 到 app-b 灰度
```

## 重要模型

在 Flagger 阶段，`app-a` 和 `app-b` 会作为同一个逻辑服务 `demo-api` 的两个版本：

```text
app-a = demo-api v1 / primary
app-b = demo-api v2 / canary
```

普通请求访问 v1，带请求头的请求访问 v2：

```bash
curl http://demo.local/version
curl -H "x-canary: true" http://demo.local/version
```

## 执行记录

所有执行步骤、命令、问题和解决方案记录在：

```text
docs/execution-log.md
```

