# =============================================================================
# Cosmos Reason1 NIM on Amazon SageMaker
# =============================================================================
# This Terraform configuration deploys NVIDIA Cosmos Reason1-7B NIM from
# AWS Marketplace to a SageMaker real-time endpoint.
#
# Reference: https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Model Package ARN mapping by region
# These ARNs are from the AWS Marketplace subscription
locals {
  model_package_map = {
    "us-east-1"    = "arn:aws:sagemaker:us-east-1:865070037744:model-package/${var.nim_package}"
    "us-east-2"    = "arn:aws:sagemaker:us-east-2:057799348421:model-package/${var.nim_package}"
    "us-west-1"    = "arn:aws:sagemaker:us-west-1:382657785993:model-package/${var.nim_package}"
    "us-west-2"    = "arn:aws:sagemaker:us-west-2:594846645681:model-package/${var.nim_package}"
    "ca-central-1" = "arn:aws:sagemaker:ca-central-1:470592106596:model-package/${var.nim_package}"
    "eu-central-1" = "arn:aws:sagemaker:eu-central-1:446921602837:model-package/${var.nim_package}"
    "eu-west-1"    = "arn:aws:sagemaker:eu-west-1:985815980388:model-package/${var.nim_package}"
    "eu-west-2"    = "arn:aws:sagemaker:eu-west-2:856760150666:model-package/${var.nim_package}"
    "eu-north-1"   = "arn:aws:sagemaker:eu-north-1:136758871317:model-package/${var.nim_package}"
    "ap-southeast-1" = "arn:aws:sagemaker:ap-southeast-1:192199979996:model-package/${var.nim_package}"
    "ap-southeast-2" = "arn:aws:sagemaker:ap-southeast-2:666831318237:model-package/${var.nim_package}"
    "ap-northeast-1" = "arn:aws:sagemaker:ap-northeast-1:977537786026:model-package/${var.nim_package}"
    "ap-northeast-2" = "arn:aws:sagemaker:ap-northeast-2:745090734665:model-package/${var.nim_package}"
    "ap-south-1"     = "arn:aws:sagemaker:ap-south-1:077584701553:model-package/${var.nim_package}"
    "sa-east-1"      = "arn:aws:sagemaker:sa-east-1:270155090741:model-package/${var.nim_package}"
  }

  model_package_arn = local.model_package_map[var.aws_region]

  tags = merge(var.tags, {
    Project   = "cosmos-reason1"
    ManagedBy = "terraform"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for SageMaker
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${var.resource_prefix}-sagemaker-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Optional S3 access policy - only created if specific bucket ARNs are provided
# This follows the principle of least privilege
resource "aws_iam_role_policy" "s3_access" {
  count = length(var.s3_bucket_arns) > 0 ? 1 : 0
  name  = "${var.resource_prefix}-s3-access"
  role  = aws_iam_role.sagemaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        # Scoped to specific bucket objects for least-privilege access
        Resource = [for arn in var.s3_bucket_arns : "${arn}/*" if !endswith(arn, "/*")]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        # Scoped to specific buckets for least-privilege access
        Resource = [for arn in var.s3_bucket_arns : arn if !endswith(arn, "/*")]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SageMaker Model
# -----------------------------------------------------------------------------

resource "aws_sagemaker_model" "cosmos_reason1" {
  name               = "${var.resource_prefix}-cosmos-reason1"
  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn

  # Required for AWS Marketplace models
  enable_network_isolation = true

  primary_container {
    model_package_name = local.model_package_arn
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# SageMaker Endpoint Configuration
# -----------------------------------------------------------------------------

resource "aws_sagemaker_endpoint_configuration" "cosmos_reason1" {
  name = "${var.resource_prefix}-cosmos-reason1-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.cosmos_reason1.name
    initial_instance_count = var.instance_count
    instance_type          = var.instance_type
    initial_variant_weight = 1.0

    # Inference AMI version for GPU instances
    inference_ami_version = "al2-ami-sagemaker-inference-gpu-2"

    # Container startup health check (model loading time)
    container_startup_health_check_timeout_in_seconds = var.container_startup_timeout

    # Model data download timeout (NIM containers need time to download model weights)
    model_data_download_timeout_in_seconds = var.model_data_download_timeout

    # Routing configuration for load balancing
    routing_config {
      routing_strategy = "LEAST_OUTSTANDING_REQUESTS"
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# SageMaker Endpoint
# -----------------------------------------------------------------------------

resource "aws_sagemaker_endpoint" "cosmos_reason1" {
  name                 = "${var.resource_prefix}-cosmos-reason1-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.cosmos_reason1.name

  tags = local.tags
}
