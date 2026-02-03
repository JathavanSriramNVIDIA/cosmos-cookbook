# Cosmos Reason1 NIM Helm Chart

NVIDIA Cosmos Reason1 NIM Helm Chart simplifies NIM deployment on Kubernetes. It aims to support deployment with a variety of possible cluster, GPU, and storage configurations.

## Prerequisites

- Kubernetes >= 1.23
- Helm >= 3.0
- NVIDIA GPU Operator installed
- GPU nodes with NVIDIA A10G, A100, or similar GPUs
- NGC API key for pulling NIM images

## Quick Start

### 1. Create NGC Secrets

```bash
export NGC_API_KEY="your-ngc-api-key"
export NAMESPACE="cosmos"

# Create namespace
kubectl create namespace $NAMESPACE

# Create NGC API key secret
kubectl create secret generic ngc-api-key \
  --from-literal=NGC_API_KEY=$NGC_API_KEY \
  -n $NAMESPACE

# Create NGC registry pull secret
kubectl create secret docker-registry ngc-registry \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY \
  -n $NAMESPACE
```

### 2. Install the Chart

```bash
helm install cosmos-reason1 ./cosmos-reason1 \
  --namespace cosmos \
  --set persistence.enabled=true \
  --set persistence.existingClaim=cosmos-model-cache
```

### 3. Verify Deployment

```bash
# Watch pod status
kubectl get pods -n cosmos -w

# Run Helm tests
helm test cosmos-reason1 -n cosmos
```

## Storage

Storage is a particular concern when setting up NIMs. Models can be quite large, and you can fill disk downloading things to emptyDirs. It is best to ensure you have persistent storage.

This chart supports four storage options:

| Option | Parameter | Use Case |
|--------|-----------|----------|
| **PVC** | `persistence.enabled=true` | Standard persistent storage |
| **PVC Templates** | `persistence.enabled=true` + `statefulSet.enabled=true` | Per-replica storage for scaling |
| **hostPath** | `hostPath.enabled=true` | Local node storage (security implications) |
| **NFS** | `nfs.enabled=true` | Shared network storage |

These options are mutually exclusive. Only enable **one** option.

### Using EFS (Recommended for AWS EKS)

```bash
helm install cosmos-reason1 ./cosmos-reason1 \
  --namespace cosmos \
  --set persistence.enabled=true \
  --set persistence.existingClaim=cosmos-model-cache \
  --set persistence.accessModes[0]=ReadWriteMany
```

## Parameters

### Deployment Parameters

| Name | Description | Default |
|------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `statefulSet.enabled` | Use StatefulSet instead of Deployment | `false` |
| `image.repository` | Container image repository | `nvcr.io/nim/nvidia/cosmos-reason1-7b` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Image pull secrets | `[{name: ngc-registry}]` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.annotations` | Service account annotations | `{}` |
| `serviceAccount.name` | Service account name | `""` |
| `podAnnotations` | Pod annotations | `{}` |
| `podSecurityContext.runAsUser` | User ID for pod | `1000` |
| `podSecurityContext.runAsGroup` | Group ID for pod | `1000` |
| `podSecurityContext.fsGroup` | Filesystem group ID | `1000` |
| `containerSecurityContext` | Container security context | `{}` |
| `terminationGracePeriodSeconds` | Termination grace period | `60` |
| `nodeSelector` | Node selector | `{nvidia.com/gpu: "true"}` |
| `tolerations` | Tolerations | GPU tolerations |
| `affinity` | Affinity rules | `{}` |

### Model Parameters

| Name | Description | Default |
|------|-------------|---------|
| `model.name` | Model name for API | `nvidia/cosmos-reason1-7b` |
| `model.nimCache` | NIM cache path | `/opt/nim/.cache` |
| `model.ngcAPISecret` | Secret name for NGC_API_KEY | `ngc-api-key` |
| `model.ngcAPIKey` | NGC API key (auto-creates secrets) | `""` |
| `model.openaiPort` | OpenAI API port | `8000` |
| `model.labels` | Extra pod labels | `{}` |
| `model.jsonLogging` | Enable JSON logging | `true` |
| `model.logLevel` | Log level (TRACE/DEBUG/INFO/WARNING/ERROR/CRITICAL) | `INFO` |

### NIM Runtime Parameters

| Name | Description | Default |
|------|-------------|---------|
| `nim.shmSize` | Shared memory size | `32Gi` |
| `nim.extraEnv` | Extra environment variables | `[]` |

### Resource Parameters

| Name | Description | Default |
|------|-------------|---------|
| `resources.limits.nvidia.com/gpu` | GPU limit | `4` |
| `resources.limits.memory` | Memory limit | `180Gi` |
| `resources.limits.cpu` | CPU limit | `48` |
| `resources.requests.nvidia.com/gpu` | GPU request | `4` |
| `resources.requests.memory` | Memory request | `90Gi` |
| `resources.requests.cpu` | CPU request | `24` |

### Service Parameters

| Name | Description | Default |
|------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `8000` |
| `service.annotations` | Service annotations | `{}` |
| `service.labels` | Service labels | `{}` |
| `service.name` | Override service name | `""` |

### Ingress Parameters

| Name | Description | Default |
|------|-------------|---------|
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class | `alb` |
| `ingress.annotations` | Ingress annotations | ALB defaults |
| `ingress.hosts` | Ingress hosts | `[{host: "", paths: [{path: /, pathType: Prefix}]}]` |
| `ingress.tls` | TLS configuration | `[]` |

### Probe Parameters

| Name | Description | Default |
|------|-------------|---------|
| `livenessProbe.enabled` | Enable liveness probe | `true` |
| `livenessProbe.method` | Probe method (http/script) | `http` |
| `livenessProbe.path` | Liveness endpoint | `/v1/health/live` |
| `livenessProbe.initialDelaySeconds` | Initial delay | `15` |
| `livenessProbe.periodSeconds` | Period | `10` |
| `livenessProbe.failureThreshold` | Failure threshold | `3` |
| `readinessProbe.enabled` | Enable readiness probe | `true` |
| `readinessProbe.path` | Readiness endpoint | `/v1/health/ready` |
| `readinessProbe.initialDelaySeconds` | Initial delay | `15` |
| `readinessProbe.periodSeconds` | Period | `10` |
| `readinessProbe.failureThreshold` | Failure threshold | `3` |
| `startupProbe.enabled` | Enable startup probe | `true` |
| `startupProbe.path` | Startup endpoint | `/v1/health/ready` |
| `startupProbe.initialDelaySeconds` | Initial delay | `40` |
| `startupProbe.periodSeconds` | Period | `10` |
| `startupProbe.failureThreshold` | Failure threshold | `180` |

### Autoscaling Parameters

| Name | Description | Default |
|------|-------------|---------|
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `1` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `autoscaling.metrics` | Custom metrics array | `[]` |
| `podDisruptionBudget.enabled` | Enable PDB | `false` |
| `podDisruptionBudget.minAvailable` | Min available pods | `1` |

### Storage Parameters

| Name | Description | Default |
|------|-------------|---------|
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.existingClaim` | Use existing PVC | `cosmos-model-cache` |
| `persistence.storageClass` | Storage class | `efs-sc` |
| `persistence.accessModes` | Access modes | `[ReadWriteMany]` |
| `persistence.size` | Storage size | `100Gi` |
| `persistence.mountPath` | Mount path | `/opt/nim/.cache` |
| `hostPath.enabled` | Enable hostPath | `false` |
| `hostPath.path` | Host path | `/model-store` |
| `nfs.enabled` | Enable NFS | `false` |
| `nfs.server` | NFS server | `nfs-server.example.com` |
| `nfs.path` | NFS path | `/exports` |
| `nfs.readOnly` | Read-only mount | `false` |
| `extraVolumes` | Additional volumes | `{}` |
| `extraVolumeMounts` | Additional volume mounts | `{}` |

### Proxy Parameters

| Name | Description | Default |
|------|-------------|---------|
| `proxyCA.enabled` | Enable proxy CA | `false` |
| `proxyCA.secretName` | CA secret name | `""` |
| `proxyCA.keyName` | Key in secret | `""` |

### Metrics Parameters

| Name | Description | Default |
|------|-------------|---------|
| `metrics.enabled` | Enable metrics | `false` |
| `metrics.serviceMonitor.enabled` | Enable ServiceMonitor | `false` |
| `metrics.serviceMonitor.additionalLabels` | Additional labels | `{}` |
| `metrics.serviceMonitor.interval` | Scrape interval | `30s` |
| `metrics.serviceMonitor.path` | Metrics path | `/metrics` |

## Examples

### Basic Deployment

```yaml
# values-basic.yaml
replicaCount: 1
resources:
  limits:
    nvidia.com/gpu: 4
persistence:
  enabled: true
  existingClaim: cosmos-model-cache
```

### With Auto-Generated Secrets

```yaml
# values-with-key.yaml
model:
  ngcAPIKey: "nvapi-xxxxx"  # Auto-creates secrets
imagePullSecrets: []  # Not needed when ngcAPIKey is set
```

### ECR Air-Gapped Deployment

```yaml
# values-ecr.yaml
image:
  repository: 123456789012.dkr.ecr.us-east-1.amazonaws.com/cosmos-reason1
imagePullSecrets: []  # EKS nodes have IAM access to ECR
```

### With ALB Ingress

```yaml
# values-ingress.yaml
ingress:
  enabled: true
  annotations:
    alb.ingress.kubernetes.io/inbound-cidrs: "10.0.0.0/8,YOUR_IP/32"
```

### With Prometheus Monitoring

```yaml
# values-metrics.yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    additionalLabels:
      release: prometheus
```

### StatefulSet with PVC Templates

```yaml
# values-statefulset.yaml
statefulSet:
  enabled: true
persistence:
  enabled: true
  existingClaim: ""  # Empty to use PVC templates
  accessModes:
    - ReadWriteOnce
  size: 100Gi
```

## Troubleshooting

### Pod stuck in Pending

Check GPU nodes:

```bash
kubectl get nodes -l nvidia.com/gpu=true
kubectl describe node <node-name>
```

### Container not starting

Check logs:

```bash
kubectl logs -f deployment/cosmos-reason1 -n cosmos
```

### Model download issues

Verify NGC credentials:

```bash
kubectl get secret ngc-api-key -n cosmos -o jsonpath='{.data.NGC_API_KEY}' | base64 -d
```

## License

Apache 2.0
