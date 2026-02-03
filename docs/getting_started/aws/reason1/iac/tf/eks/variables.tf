# =============================================================================
# Variables for Cosmos Reason1 NIM on AWS EKS Deployment
# =============================================================================
# This deploys an EKS cluster with GPU node groups for running NVIDIA NIMs.
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "cosmos"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.(2[89]|3[0-1])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.28, 1.29, 1.30, or 1.31."
  }
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "availability_zones_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zones_count >= 2 && var.availability_zones_count <= 3
    error_message = "Availability zones count must be between 2 and 3."
  }
}

# -----------------------------------------------------------------------------
# Node Group Configuration
# -----------------------------------------------------------------------------

variable "gpu_instance_type" {
  description = <<-EOT
    EC2 instance type for GPU nodes.
    Requirements from NVIDIA:
    - NVIDIA Ampere architecture or later
    - At least 90GB RAM
    - Sufficient GPU memory

    Recommended options:
    - g5.12xlarge  : 4x A10G (96GB VRAM), 192GB RAM - Balanced
    - g5.24xlarge  : 4x A10G (96GB VRAM), 384GB RAM - Higher memory
    - g5.48xlarge  : 8x A10G (192GB VRAM), 768GB RAM - Maximum A10G
    - p4d.24xlarge : 8x A100 (320GB VRAM), 1152GB RAM - Maximum performance
  EOT
  type        = string
  default     = "g5.12xlarge"

  validation {
    condition = contains([
      # G5 instances (A10G GPUs)
      "g5.xlarge", "g5.2xlarge", "g5.4xlarge", "g5.8xlarge",
      "g5.12xlarge", "g5.16xlarge", "g5.24xlarge", "g5.48xlarge",
      # G6 instances (L4 GPUs)
      "g6.xlarge", "g6.2xlarge", "g6.4xlarge", "g6.8xlarge",
      "g6.12xlarge", "g6.16xlarge", "g6.24xlarge", "g6.48xlarge",
      # P4d instances (A100 GPUs)
      "p4d.24xlarge",
      # P5 instances (H100 GPUs)
      "p5.48xlarge"
    ], var.gpu_instance_type)
    error_message = "Instance type must be a supported GPU instance type for Cosmos Reason1."
  }
}

variable "gpu_node_count" {
  description = "Number of GPU nodes (desired capacity)"
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_count >= 1 && var.gpu_node_count <= 10
    error_message = "GPU node count must be between 1 and 10."
  }
}

variable "gpu_node_min_count" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 1
}

variable "gpu_node_max_count" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 3
}

variable "gpu_node_disk_size" {
  description = "Disk size in GB for GPU nodes"
  type        = number
  default     = 200

  validation {
    condition     = var.gpu_node_disk_size >= 100
    error_message = "GPU node disk size must be at least 100GB."
  }
}

variable "gpu_ami_type" {
  description = "AMI type for GPU nodes (AL2_x86_64_GPU recommended for NVIDIA)"
  type        = string
  default     = "AL2_x86_64_GPU"

  validation {
    condition     = contains(["AL2_x86_64_GPU", "AL2023_x86_64_NVIDIA"], var.gpu_ami_type)
    error_message = "GPU AMI type must be AL2_x86_64_GPU or AL2023_x86_64_NVIDIA."
  }
}

# -----------------------------------------------------------------------------
# Add-ons and Features
# -----------------------------------------------------------------------------

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler for automatic node scaling"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ECR Configuration (for Air-Gapped Deployments)
# -----------------------------------------------------------------------------

variable "create_ecr_repository" {
  description = <<-EOT
    Create an ECR repository for storing NIM images locally.
    Enable this for air-gapped deployments where NGC access is not available.
    After creation, push the NIM image to ECR and update the Helm values.
  EOT
  type        = bool
  default     = false
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for NIM images"
  type        = string
  default     = "cosmos-reason1"
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for ECR repository"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

variable "enable_metrics_server" {
  description = "Enable Metrics Server for resource metrics"
  type        = bool
  default     = true
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller for ALB/NLB ingress"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    List of CIDR blocks allowed to access the public EKS endpoint.
    SECURITY: The default allows access from anywhere. For production,
    restrict to your IP/network (e.g., ["YOUR_IP/32", "10.0.0.0/8"]).
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network traffic auditing"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC Flow Logs in CloudWatch"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention must be a valid CloudWatch Logs retention period."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    ARN of a customer-managed KMS key for encryption.
    If null, AWS-managed keys are used.
    Used for: EKS secrets, EFS, ECR (if enabled).
  EOT
  type        = string
  default     = null
}

variable "enable_secrets_encryption" {
  description = "Enable envelope encryption for Kubernetes secrets using KMS"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
