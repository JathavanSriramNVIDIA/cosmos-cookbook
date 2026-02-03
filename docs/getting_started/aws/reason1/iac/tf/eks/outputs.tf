# =============================================================================
# Outputs for Cosmos Reason1 NIM on AWS EKS
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster Information
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

# -----------------------------------------------------------------------------
# VPC Information
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

# -----------------------------------------------------------------------------
# Node Group Information
# -----------------------------------------------------------------------------

output "gpu_node_group_name" {
  description = "Name of the GPU node group"
  value       = aws_eks_node_group.gpu.node_group_name
}

output "gpu_node_group_arn" {
  description = "ARN of the GPU node group"
  value       = aws_eks_node_group.gpu.arn
}

output "gpu_instance_type" {
  description = "Instance type used for GPU nodes"
  value       = var.gpu_instance_type
}

# -----------------------------------------------------------------------------
# Kubernetes Configuration
# -----------------------------------------------------------------------------

output "cosmos_namespace" {
  description = "Kubernetes namespace for Cosmos workloads"
  value       = kubernetes_namespace.cosmos.metadata[0].name
}

output "ngc_secret_name" {
  description = "Name of the NGC API key secret"
  value       = kubernetes_secret.ngc_api_key.metadata[0].name
}

output "ngc_registry_secret_name" {
  description = "Name of the NGC registry pull secret"
  value       = kubernetes_secret.ngc_registry.metadata[0].name
}

# -----------------------------------------------------------------------------
# OIDC Provider
# -----------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# -----------------------------------------------------------------------------
# ECR Information (for Air-Gapped Deployments)
# -----------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "ECR repository URL for NIM images (if created)"
  value       = var.create_ecr_repository ? aws_ecr_repository.nim[0].repository_url : null
}

output "ecr_repository_arn" {
  description = "ECR repository ARN (if created)"
  value       = var.create_ecr_repository ? aws_ecr_repository.nim[0].arn : null
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = var.create_ecr_repository ? aws_ecr_repository.nim[0].registry_id : null
}

output "ecr_push_commands" {
  description = "Commands to push NIM image to ECR"
  value       = var.create_ecr_repository ? <<-EOT

    # 1. Authenticate Docker to ECR
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.nim[0].repository_url}

    # 2. Pull NIM image from NGC (requires NGC_API_KEY)
    echo $NGC_API_KEY | docker login nvcr.io -u '$oauthtoken' --password-stdin
    docker pull nvcr.io/nim/nvidia/cosmos-reason1-7b:latest

    # 3. Tag for ECR
    docker tag nvcr.io/nim/nvidia/cosmos-reason1-7b:latest ${aws_ecr_repository.nim[0].repository_url}:latest

    # 4. Push to ECR
    docker push ${aws_ecr_repository.nim[0].repository_url}:latest

  EOT : null
}

# -----------------------------------------------------------------------------
# EFS Information
# -----------------------------------------------------------------------------

output "efs_file_system_id" {
  description = "ID of the EFS file system for model cache"
  value       = aws_efs_file_system.model_cache.id
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.model_cache.arn
}

output "efs_access_point_id" {
  description = "ID of the EFS access point for Cosmos workloads"
  value       = aws_efs_access_point.cosmos.id
}

output "model_cache_pvc_name" {
  description = "Name of the PersistentVolumeClaim for model cache"
  value       = kubernetes_persistent_volume_claim.model_cache.metadata[0].name
}

# -----------------------------------------------------------------------------
# Connection Commands
# -----------------------------------------------------------------------------

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}

output "setup_instructions" {
  description = "Instructions for completing the setup"
  value       = <<-EOT

    ============================================================
    EKS CLUSTER DEPLOYMENT COMPLETE
    ============================================================

    Cluster: ${aws_eks_cluster.main.name}
    Region:  ${var.aws_region}
    EFS:     ${aws_efs_file_system.model_cache.id} (for model cache)

    NEXT STEPS:

    1. Configure kubectl:
       aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}

    2. Verify cluster access:
       kubectl get nodes

    3. Verify EFS is ready:
       kubectl get pv,pvc -n cosmos

    4. Update NGC secrets with your API key:
       kubectl create secret generic ngc-api-key \
         --from-literal=NGC_API_KEY=your-ngc-api-key \
         -n cosmos --dry-run=client -o yaml | kubectl apply -f -

       kubectl create secret docker-registry ngc-registry \
         --docker-server=nvcr.io \
         --docker-username='$oauthtoken' \
         --docker-password=your-ngc-api-key \
         -n cosmos --dry-run=client -o yaml | kubectl apply -f -

    5. Deploy Cosmos Reason1 NIM using Helm (with EFS cache):
       helm install cosmos-reason1 ./helm/cosmos-reason1 \
         --namespace cosmos \
         --set persistence.enabled=true \
         --set persistence.existingClaim=cosmos-model-cache

    6. Wait for the pod to be ready:
       kubectl get pods -n cosmos -w

    7. Access the API:
       kubectl port-forward svc/cosmos-reason1 8000:8000 -n cosmos
       curl http://localhost:8000/v1/health/ready

    MODEL CACHE BENEFITS:
    - First deployment: ~5-10 min (downloads model to EFS)
    - Subsequent deployments: ~1-2 min (loads from EFS cache)
    - Cache is shared across all pods and survives restarts

    ============================================================
  EOT
}

# -----------------------------------------------------------------------------
# Security Information
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if created)"
  value       = var.enable_secrets_encryption && var.kms_key_arn == null ? aws_kms_key.eks[0].arn : var.kms_key_arn
}

output "vpc_flow_logs_enabled" {
  description = "Whether VPC Flow Logs are enabled"
  value       = var.enable_vpc_flow_logs
}

output "secrets_encryption_enabled" {
  description = "Whether EKS secrets encryption is enabled"
  value       = var.enable_secrets_encryption
}

# -----------------------------------------------------------------------------
# Region Information
# -----------------------------------------------------------------------------

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}
