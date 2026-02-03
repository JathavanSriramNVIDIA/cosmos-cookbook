# Cosmos Reason1 NIM on AWS EKS

This Terraform configuration deploys an AWS EKS cluster with GPU node groups for running NVIDIA Cosmos Reason1 NIM containers.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                          VPC                               │  │
│  │  ┌─────────────────┐      ┌─────────────────┐             │  │
│  │  │  Public Subnet  │      │  Public Subnet  │             │  │
│  │  │    (AZ-1)       │      │    (AZ-2)       │             │  │
│  │  │  ┌───────────┐  │      │  ┌───────────┐  │             │  │
│  │  │  │ NAT GW    │  │      │  │ NAT GW    │  │             │  │
│  │  │  └───────────┘  │      │  └───────────┘  │             │  │
│  │  └─────────────────┘      └─────────────────┘             │  │
│  │                                                            │  │
│  │  ┌─────────────────┐      ┌─────────────────┐             │  │
│  │  │ Private Subnet  │      │ Private Subnet  │             │  │
│  │  │    (AZ-1)       │      │    (AZ-2)       │             │  │
│  │  │  ┌───────────┐  │      │  ┌───────────┐  │             │  │
│  │  │  │ GPU Node  │  │      │  │ GPU Node  │  │             │  │
│  │  │  │ (g5.12xl) │  │      │  │ (g5.12xl) │  │             │  │
│  │  │  └───────────┘  │      │  └───────────┘  │             │  │
│  │  │       │         │      │       │         │             │  │
│  │  │       └─────────┼──────┼───────┘         │             │  │
│  │  │           ┌─────┴─────┐                  │             │  │
│  │  │           │    EFS    │ (Model Cache)    │             │  │
│  │  │           └───────────┘                  │             │  │
│  │  └─────────────────┘      └─────────────────┘             │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────┐              │  │
│  │  │           EKS Control Plane              │              │  │
│  │  └─────────────────────────────────────────┘              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features

- **GPU Node Groups**: Managed node groups with NVIDIA A10G/A100 GPUs
- **EFS Model Cache**: Shared storage for caching model checkpoints
- **NVIDIA Device Plugin**: Automatic GPU resource management
- **EFS CSI Driver**: Native Kubernetes storage integration
- **Cluster Autoscaler**: Automatic node scaling based on demand

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0.0
- kubectl
- Helm >= 3.0
- GPU instance quota (g5.12xlarge or similar)

## Quick Start

1. **Configure variables:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Deploy the infrastructure:**

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Configure kubectl:**

   ```bash
   aws eks update-kubeconfig --name $(terraform output -raw cluster_name) --region $(terraform output -raw region)
   ```

4. **Verify cluster access:**

   ```bash
   kubectl get nodes
   ```

5. **Verify EFS is ready:**

   ```bash
   kubectl get pv,pvc -n cosmos
   ```

   You should see the model cache PV and PVC in `Bound` status.

6. **Configure NGC secrets:**

   ```bash
   export NGC_API_KEY="your-ngc-api-key"

   # Create NGC API key secret
   kubectl create secret generic ngc-api-key \
     --from-literal=NGC_API_KEY=$NGC_API_KEY \
     -n cosmos

   # Create NGC registry pull secret
   kubectl create secret docker-registry ngc-registry \
     --docker-server=nvcr.io \
     --docker-username='$oauthtoken' \
     --docker-password=$NGC_API_KEY \
     -n cosmos
   ```

7. **Deploy Cosmos Reason1 NIM (with EFS cache):**

   ```bash
   helm install cosmos-reason1 ./helm/cosmos-reason1 \
     --namespace cosmos \
     --set persistence.enabled=true \
     --set persistence.existingClaim=cosmos-model-cache
   ```

8. **Wait for the pod to be ready:**

   ```bash
   kubectl get pods -n cosmos -w
   ```

   **Startup times:**
   - First deployment: ~5-10 minutes (downloads model to EFS)
   - Subsequent deployments: ~1-2 minutes (loads from EFS cache)

9. **Access the API:**

    **Option A: Port forwarding (no external exposure - recommended for dev)**

    ```bash
    kubectl port-forward svc/cosmos-reason1 8000:8000 -n cosmos
    curl http://localhost:8000/v1/health/ready
    ```

    **Option B: AWS ALB with IP restrictions (for team/production access)**

    ```bash
    # Get your public IP
    MY_IP=$(curl -s ifconfig.me)

    # Deploy with ALB and IP restriction
    helm upgrade cosmos-reason1 ./helm/cosmos-reason1 \
      --namespace cosmos \
      --set ingress.enabled=true \
      --set ingress.annotations."alb\.ingress\.kubernetes\.io/inbound-cidrs"="$MY_IP/32"

    # Get ALB endpoint
    kubectl get ingress -n cosmos
    ```

## Configuration

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `resource_prefix` | Prefix for resource names | `cosmos` |
| `kubernetes_version` | EKS Kubernetes version | `1.31` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `gpu_instance_type` | GPU instance type | `g5.12xlarge` |
| `gpu_node_count` | Number of GPU nodes | `1` |
| `enable_cluster_autoscaler` | Enable Cluster Autoscaler | `true` |
| `create_ecr_repository` | Create ECR for air-gapped deployments | `false` |
| `ecr_repository_name` | ECR repository name | `cosmos-reason1` |

### EFS Model Cache

The deployment includes an EFS file system for caching model checkpoints:

| Feature | Benefit |
|---------|---------|
| **Shared Storage** | Model cache shared across all pods |
| **Persistence** | Cache survives pod restarts and scaling |
| **Fast Startup** | Subsequent pods start in ~1-2 min vs 10+ min |
| **Cost Efficient** | Download model once, use many times |
| **Multi-AZ** | Mount targets in each availability zone |

### GPU Instance Types

| Instance Type | GPUs | GPU Memory | RAM | Use Case |
|---------------|------|------------|-----|----------|
| `g5.12xlarge` | 4x A10G | 96GB | 192GB | Recommended for Reason1 |
| `g5.24xlarge` | 4x A10G | 96GB | 384GB | Higher memory workloads |
| `g5.48xlarge` | 8x A10G | 192GB | 768GB | Maximum A10G capacity |
| `p4d.24xlarge` | 8x A100 | 320GB | 1152GB | Maximum performance |

## Helm Chart

The included Helm chart (`helm/cosmos-reason1`) provides:

- Deployment with GPU resource requests
- Service for API access
- Proper tolerations for GPU nodes
- Health probes for reliability
- Optional Ingress for external access
- Optional HPA for auto-scaling
- PVC for model caching

### Customizing the Helm Chart

```bash
# Install with custom values
helm install cosmos-reason1 ./helm/cosmos-reason1 \
  --namespace cosmos \
  --set replicaCount=2 \
  --set resources.limits."nvidia\.com/gpu"=4

# Or use a values file
helm install cosmos-reason1 ./helm/cosmos-reason1 \
  --namespace cosmos \
  -f my-values.yaml
```

## Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API endpoint |
| `configure_kubectl` | Command to configure kubectl |
| `cosmos_namespace` | Kubernetes namespace for Cosmos |
| `efs_file_system_id` | EFS file system ID for model cache |
| `model_cache_pvc_name` | Name of the model cache PVC |
| `ecr_repository_url` | ECR repository URL (if created) |
| `ecr_push_commands` | Commands to push NIM image to ECR |

## Clean Up

```bash
# Remove Helm release
helm uninstall cosmos-reason1 -n cosmos

# Destroy infrastructure
terraform destroy
```

## Troubleshooting

### Pods stuck in Pending

Check if GPU nodes are ready:

```bash
kubectl get nodes -l nvidia.com/gpu=true
kubectl describe node <node-name>
```

### NIM container not starting

Check logs:

```bash
kubectl logs -f deployment/cosmos-reason1 -n cosmos
```

### NVIDIA device plugin issues

Verify the device plugin is running:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin
kubectl logs -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin
```

## Air-Gapped Deployment (ECR)

For environments without internet access or NGC connectivity, you can use AWS ECR to store NIM images.

### 1. Enable ECR in Terraform

```hcl
# terraform.tfvars
create_ecr_repository = true
ecr_repository_name   = "cosmos-reason1"
```

### 2. Deploy Infrastructure

```bash
terraform apply
```

### 3. Push NIM Image to ECR

From a machine with NGC and internet access:

```bash
# Get ECR repository URL
ECR_REPO=$(terraform output -raw ecr_repository_url)

# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Pull from NGC
echo $NGC_API_KEY | docker login nvcr.io -u '$oauthtoken' --password-stdin
docker pull nvcr.io/nim/nvidia/cosmos-reason1-7b:latest

# Tag and push to ECR
docker tag nvcr.io/nim/nvidia/cosmos-reason1-7b:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### 4. Deploy Using ECR Image

```bash
ECR_REPO=$(terraform output -raw ecr_repository_url)

helm install cosmos-reason1 ./helm/cosmos-reason1 \
  --namespace cosmos \
  --set image.repository=$ECR_REPO \
  --set imagePullSecrets=[] \
  --set persistence.enabled=true \
  --set persistence.existingClaim=cosmos-model-cache
```

## Security Features

| Feature | Default | Description |
|---------|---------|-------------|
| **VPC Flow Logs** | ✅ Enabled | Network traffic auditing to CloudWatch |
| **EKS Secrets Encryption** | ✅ Enabled | Envelope encryption with KMS |
| **Private Subnets** | ✅ Enabled | GPU nodes in private subnets only |
| **EFS Encryption** | ✅ Enabled | Encryption at rest (KMS optional) |
| **ECR Scanning** | ✅ Enabled | Vulnerability scanning on push |
| **IRSA** | ✅ Enabled | IAM Roles for Service Accounts |
| **EKS Logging** | ✅ Enabled | API, audit, authenticator logs |

### Security Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_vpc_flow_logs` | `true` | Enable VPC Flow Logs |
| `enable_secrets_encryption` | `true` | Enable EKS secrets encryption |
| `kms_key_arn` | `null` | Customer-managed KMS key (optional) |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | **Restrict for production!** |

### Production Recommendations

1. **Restrict EKS endpoint access**: Set `cluster_endpoint_public_access_cidrs` to your IP/network
2. **Use customer-managed KMS**: Provide `kms_key_arn` for compliance requirements
3. **Enable private-only access**: Set `cluster_endpoint_public_access = false` if using VPN
4. **Add Network Policies**: Deploy Calico or Cilium for pod-level network isolation
5. **Use AWS Secrets Manager**: Integrate with External Secrets Operator for production secrets
