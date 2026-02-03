# =============================================================================
# Variables for Cosmos Reason1 NIM Deployment
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "ca-central-1", "eu-central-1", "eu-west-1", "eu-west-2", "eu-north-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
      "ap-south-1", "sa-east-1"
    ], var.aws_region)
    error_message = "Region must be one of the supported AWS Marketplace regions for Cosmos Reason1."
  }
}

variable "nim_package" {
  description = <<-EOT
    The NIM model package name from AWS Marketplace subscription.
    After subscribing to the model, you'll receive the package name.
    Example: "nvidia-cosmos-reason1-7b-1-0-abc123"
  EOT
  type        = string
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

variable "instance_type" {
  description = <<-EOT
    SageMaker instance type for the endpoint.
    Recommended:
    - ml.g5.12xlarge: 4x A10G GPUs, 96GB VRAM (batch, cost-effective)
    - ml.g6e.xlarge: 1x L40S GPU, 48GB VRAM (real-time, recommended)
    - ml.g5.24xlarge: 4x A10G GPUs, 96GB VRAM (higher throughput)
  EOT
  type        = string
  default     = "ml.g5.12xlarge"

  validation {
    condition = contains([
      "ml.g5.xlarge", "ml.g5.2xlarge", "ml.g5.4xlarge", "ml.g5.8xlarge",
      "ml.g5.12xlarge", "ml.g5.24xlarge", "ml.g5.48xlarge",
      "ml.g6e.xlarge", "ml.g6e.2xlarge", "ml.g6e.4xlarge", "ml.g6e.8xlarge",
      "ml.p4d.24xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a supported GPU instance type for Cosmos Reason1."
  }
}

variable "instance_count" {
  description = "Number of instances for the endpoint"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

variable "container_startup_timeout" {
  description = "Timeout in seconds for container startup health check (model loading can take time)"
  type        = number
  default     = 3600 # 1 hour - NIM containers can take significant time to load

  validation {
    condition     = var.container_startup_timeout >= 60 && var.container_startup_timeout <= 3600
    error_message = "Container startup timeout must be between 60 and 3600 seconds."
  }
}

variable "model_data_download_timeout" {
  description = "Timeout in seconds for model data download (NIM containers download large model weights)"
  type        = number
  default     = 3600 # 1 hour - large models need time to download

  validation {
    condition     = var.model_data_download_timeout >= 60 && var.model_data_download_timeout <= 3600
    error_message = "Model data download timeout must be between 60 and 3600 seconds."
  }
}

variable "s3_bucket_arns" {
  description = <<-EOT
    List of S3 bucket ARNs the SageMaker execution role is allowed to access.
    If empty, no additional S3 access policy is attached (SageMaker managed
    policy provides access to default SageMaker buckets).
    Example: ["arn:aws:s3:::my-data-bucket", "arn:aws:s3:::my-data-bucket/*"]
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
