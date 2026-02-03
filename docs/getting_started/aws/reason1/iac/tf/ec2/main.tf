# =============================================================================
# Cosmos Reason1 NIM on AWS EC2 GPU Instance
# =============================================================================
# This Terraform configuration deploys a single AWS GPU instance with a
# dedicated VPC and all necessary networking and security for running
# NVIDIA Cosmos Reason1 NIM.
#
# Access is via AWS Systems Manager Session Manager (no SSH required).
#
# Reference: https://docs.nvidia.com/nim/cosmos/latest/prerequisites.html
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

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Get the latest Deep Learning AMI with NVIDIA drivers pre-installed
data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) *"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  # Use specified AZs if provided, otherwise auto-select first 2 available
  # G5/G6 GPU instances may not be available in all AZs
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Project   = "cosmos-reason1"
    ManagedBy = "terraform"
  })

  # Minimal user data - only ensures SSM agent is running
  # All software configuration is handled by Ansible for better control and idempotency
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Log all output
    exec > >(tee /var/log/user-data.log) 2>&1
    echo "Starting user-data script at $(date)"

    # Ensure SSM Agent is installed and running (usually pre-installed on Ubuntu AMIs)
    if ! systemctl is-active --quiet amazon-ssm-agent 2>/dev/null; then
        if ! systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service 2>/dev/null; then
            echo "Installing SSM Agent..."
            snap install amazon-ssm-agent --classic
            systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
            systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
        fi
    fi

    echo "User-data script completed at $(date)"
    echo "Run Ansible playbook to complete software configuration."
  EOF
}

# =============================================================================
# VPC and Networking
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

resource "aws_vpc" "cosmos" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-vpc"
  })
}

# -----------------------------------------------------------------------------
# Internet Gateway (for public subnets / NAT Gateway)
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "cosmos" {
  vpc_id = aws_vpc.cosmos.id

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-igw"
  })
}

# -----------------------------------------------------------------------------
# Subnets
# -----------------------------------------------------------------------------

# Public subnets (for NAT Gateway)
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.cosmos.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # No auto-assign public IPs

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-public-${local.azs[count.index]}"
    Type = "public"
  })
}

# Private subnets (for EC2 instance)
resource "aws_subnet" "private" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.cosmos.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index + length(local.azs))
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-private-${local.azs[count.index]}"
    Type = "private"
  })
}

# -----------------------------------------------------------------------------
# NAT Gateway (for private subnet internet access)
# -----------------------------------------------------------------------------

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-nat-eip"
  })

  depends_on = [aws_internet_gateway.cosmos]
}

# NAT Gateway in first public subnet
resource "aws_nat_gateway" "cosmos" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-nat"
  })

  depends_on = [aws_internet_gateway.cosmos]
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

# Public route table (routes to Internet Gateway)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cosmos.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cosmos.id
  }

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-public-rt"
  })
}

# Private route table (routes to NAT Gateway)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.cosmos.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.cosmos.id
  }

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-private-rt"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate private subnets with private route table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs (for network monitoring)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.resource_prefix}-cosmos-flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = local.tags
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.resource_prefix}-cosmos-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.resource_prefix}-cosmos-vpc-flow-logs-policy"
  role  = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        # Scoped to specific log group for least-privilege access
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "cosmos" {
  count                = var.enable_vpc_flow_logs ? 1 : 0
  vpc_id               = aws_vpc.cosmos.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  iam_role_arn         = aws_iam_role.vpc_flow_logs[0].arn

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-flow-log"
  })
}

# =============================================================================
# VPC Endpoints (for AWS service access without internet)
# =============================================================================

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.resource_prefix}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.cosmos.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-vpc-endpoints-sg"
  })
}

# SSM endpoint (required for Session Manager)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.cosmos.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-ssm-endpoint"
  })
}

# SSM Messages endpoint (required for Session Manager)
resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.cosmos.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-ssmmessages-endpoint"
  })
}

# EC2 Messages endpoint (required for Session Manager)
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.cosmos.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-ec2messages-endpoint"
  })
}

# S3 Gateway endpoint (for ECR layer downloads, free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.cosmos.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-s3-endpoint"
  })
}

# =============================================================================
# Security Group
# =============================================================================

resource "aws_security_group" "cosmos" {
  name        = "${var.resource_prefix}-cosmos-sg"
  description = "Security group for Cosmos Reason1 NIM on EC2 (Session Manager access)"
  vpc_id      = aws_vpc.cosmos.id

  # NIM API access (default port 8000) - Optional, only if direct API access needed
  dynamic "ingress" {
    for_each = length(var.allowed_api_cidrs) > 0 ? [1] : []
    content {
      description = "NIM API access"
      from_port   = 8000
      to_port     = 8000
      protocol    = "tcp"
      cidr_blocks = var.allowed_api_cidrs
    }
  }

  # Allow outbound HTTPS (for AWS APIs, NGC registry, etc.)
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTP (for some package managers)
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound DNS
  egress {
    description = "DNS outbound UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS outbound TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-sg"
  })
}

# =============================================================================
# IAM Role for EC2 with SSM Access
# =============================================================================

resource "aws_iam_role" "ec2_role" {
  name = "${var.resource_prefix}-cosmos-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# SSM Managed Instance Core - Required for Session Manager
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent (optional, for enhanced monitoring)
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count      = var.enable_detailed_monitoring ? 1 : 0
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# S3 access for Ansible SSM file transfers (required)
resource "aws_iam_role_policy" "ansible_s3_access" {
  name = "${var.resource_prefix}-ansible-s3-access"
  role = aws_iam_role.ec2_role.id

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
        Resource = "${aws_s3_bucket.ansible.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.ansible.arn
      }
    ]
  })
}

# S3 access for data loading (optional, scoped to specific buckets if provided)
resource "aws_iam_role_policy" "s3_data_access" {
  count = var.s3_bucket_arns != null ? 1 : 0
  name  = "${var.resource_prefix}-s3-data-access"
  role  = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arns
      }
    ]
  })
}

resource "aws_iam_instance_profile" "cosmos" {
  name = "${var.resource_prefix}-cosmos-profile"
  role = aws_iam_role.ec2_role.name

  tags = local.tags
}

# =============================================================================
# S3 Bucket for Ansible SSM File Transfers
# =============================================================================

resource "aws_s3_bucket" "ansible" {
  bucket_prefix = "${var.resource_prefix}-ansible-"
  force_destroy = true # Allow deletion even if not empty

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-ansible-bucket"
  })
}

resource "aws_s3_bucket_versioning" "ansible" {
  bucket = aws_s3_bucket.ansible.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible" {
  bucket = aws_s3_bucket.ansible.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ansible" {
  bucket = aws_s3_bucket.ansible.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible" {
  bucket = aws_s3_bucket.ansible.id

  rule {
    id     = "cleanup-old-files"
    status = "Enabled"

    expiration {
      days = 1 # Delete files after 1 day
    }
  }
}

# =============================================================================
# EC2 GPU Instance
# =============================================================================

resource "aws_instance" "cosmos" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.deep_learning.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.cosmos.id]
  iam_instance_profile   = aws_iam_instance_profile.cosmos.name

  # No key pair needed - using Session Manager
  # key_name = ... (removed)

  # Root volume - needs to be large for NIM container and model weights
  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 250
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = var.kms_key_arn
  }

  # User data for initial setup
  user_data_base64 = base64encode(local.user_data)

  # Enable detailed monitoring
  monitoring = var.enable_detailed_monitoring

  # Metadata options
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2          # Allow container access to IMDS
  }

  tags = merge(local.tags, {
    Name = "${var.resource_prefix}-cosmos-gpu"
  })

  lifecycle {
    ignore_changes = [ami] # Don't recreate instance when AMI updates
  }

  depends_on = [
    aws_nat_gateway.cosmos,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages
  ]
}
