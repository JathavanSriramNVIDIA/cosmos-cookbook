# =============================================================================
# Variables for Cosmos Reason1 NIM on EC2 Deployment
# =============================================================================
# Access is via AWS Systems Manager Session Manager (no SSH required).
# A dedicated VPC with private subnets is created for security.
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "nim"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
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

variable "availability_zones" {
  description = <<-EOT
    List of availability zones to use. If empty, automatically selects AZs.
    G5/G6 GPU instances may not be available in all AZs - specify AZs where
    GPU instance capacity is available in your region.
    Example: ["us-east-1c", "us-east-1f"]
  EOT
  type        = list(string)
  default     = []
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs for network monitoring"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain VPC flow logs"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention must be a valid CloudWatch Logs retention period."
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance Configuration
# -----------------------------------------------------------------------------

variable "instance_type" {
  description = <<-EOT
    EC2 instance type with GPU support for Cosmos Reason1 NIM.
    Requirements from NVIDIA:
    - NVIDIA Ampere architecture or later
    - At least 90GB RAM
    - Sufficient GPU memory (see model requirements)

    Recommended options:
    - g5.12xlarge  : 4x A10G (96GB VRAM), 192GB RAM - Balanced
    - g5.24xlarge  : 4x A10G (96GB VRAM), 384GB RAM - Higher memory
    - g5.48xlarge  : 8x A10G (192GB VRAM), 768GB RAM - Maximum A10G
    - p4d.24xlarge : 8x A100 (320GB VRAM), 1152GB RAM - Maximum performance
    - g6.12xlarge  : 4x L4 (192GB VRAM), 192GB RAM - Latest generation
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
    ], var.instance_type)
    error_message = "Instance type must be a supported GPU instance type for Cosmos Reason1."
  }
}

variable "ami_id" {
  description = <<-EOT
    Custom AMI ID to use. If empty, the latest Deep Learning AMI with
    NVIDIA drivers pre-installed will be used.
  EOT
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = <<-EOT
    Size of the root EBS volume in GB.
    NVIDIA requirements: At least 100GB for container and model.
    Recommended: 200GB+ for comfortable operation.
  EOT
  type        = number
  default     = 200

  validation {
    condition     = var.root_volume_size >= 100
    error_message = "Root volume size must be at least 100GB per NVIDIA requirements."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    ARN of the KMS key to use for EBS encryption.
    If empty, the default AWS-managed key is used.
  EOT
  type        = string
  default     = null
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for the instance"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "allowed_api_cidrs" {
  description = <<-EOT
    List of CIDR blocks allowed to access the NIM API (port 8000).
    Leave empty to disable direct API access (recommended - use SSM port forwarding instead).
    Example: ["10.0.0.0/8"] for internal network access
  EOT
  type        = list(string)
  default     = []
}

variable "s3_bucket_arns" {
  description = <<-EOT
    List of S3 bucket ARNs the instance is allowed to access.
    If null, no S3 access policy is attached.
    Example: ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
  EOT
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
