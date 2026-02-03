# =============================================================================
# Outputs for Cosmos Reason1 NIM on EC2 Deployment
# =============================================================================
# Access is via AWS Systems Manager Session Manager (no SSH required).
# Instance is deployed in a private subnet within a dedicated VPC.
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.cosmos.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.cosmos.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "ansible_s3_bucket" {
  description = "S3 bucket name for Ansible SSM file transfers"
  value       = aws_s3_bucket.ansible.id
}

# -----------------------------------------------------------------------------
# EC2 Instance Outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.cosmos.id
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.cosmos.private_ip
}

output "security_group_id" {
  description = "ID of the instance security group"
  value       = aws_security_group.cosmos.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.ec2_role.arn
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "instance_type" {
  description = "Instance type used"
  value       = var.instance_type
}

output "ami_id" {
  description = "AMI ID used for the instance"
  value       = aws_instance.cosmos.ami
}

# -----------------------------------------------------------------------------
# Session Manager Commands
# -----------------------------------------------------------------------------

output "ssm_start_session_command" {
  description = "AWS CLI command to start a Session Manager session"
  value       = "aws ssm start-session --target ${aws_instance.cosmos.id} --region ${var.aws_region}"
}

output "ssm_port_forward_command" {
  description = "AWS CLI command to forward NIM API port (8000) to localhost"
  value       = "aws ssm start-session --target ${aws_instance.cosmos.id} --region ${var.aws_region} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8000\"],\"localPortNumber\":[\"8000\"]}'"
}

output "ssm_run_command" {
  description = "Example AWS CLI command to run a command on the instance"
  value       = "aws ssm send-command --instance-ids ${aws_instance.cosmos.id} --document-name AWS-RunShellScript --parameters 'commands=[\"nvidia-smi\"]' --region ${var.aws_region}"
}

# -----------------------------------------------------------------------------
# API Access
# -----------------------------------------------------------------------------

output "nim_api_endpoint_local" {
  description = "NIM API endpoint when using port forwarding"
  value       = "http://localhost:8000"
}

output "nim_api_endpoint_private" {
  description = "NIM API endpoint using private IP (from within VPC)"
  value       = "http://${aws_instance.cosmos.private_ip}:8000"
}

# -----------------------------------------------------------------------------
# Setup Instructions
# -----------------------------------------------------------------------------

output "setup_instructions" {
  description = "Instructions for setting up and running Cosmos Reason1 NIM"
  value       = <<-EOT

    ============================================================
    COSMOS REASON1 NIM ON EC2 - SETUP INSTRUCTIONS
    ============================================================

    INFRASTRUCTURE DEPLOYED:
    - VPC: ${aws_vpc.cosmos.id} (${var.vpc_cidr})
    - Private Subnet: ${aws_subnet.private[0].id}
    - NAT Gateway IP: ${aws_eip.nat.public_ip}
    - Instance: ${aws_instance.cosmos.id} (${aws_instance.cosmos.private_ip})

    The instance is in a PRIVATE subnet with no public IP.
    All access is through AWS Systems Manager Session Manager.

    STEP 1: CONFIGURE SOFTWARE WITH ANSIBLE
    ----------------------------------------
    All software configuration (Docker, NVIDIA Container Toolkit, etc.)
    is handled by Ansible for better control and idempotency.

    # Install Ansible requirements
    pip install boto3 botocore ansible

    # Set your NGC API key
    export NGC_API_KEY="your-ngc-api-key"

    # Update inventory with instance ID and bucket name
    cd ansible
    sed -i "s/i-xxxxxxxxxxxxxxxxx/${aws_instance.cosmos.id}/" inventory_ssm.yml
    sed -i "s/us-east-1/${var.aws_region}/" inventory_ssm.yml
    sed -i "s/ANSIBLE_BUCKET_NAME/${aws_s3_bucket.ansible.id}/" inventory_ssm.yml

    # Wait for instance to be ready (1-2 minutes)
    sleep 120

    # Run the playbook
    ansible-playbook -i inventory_ssm.yml setup_cosmos_nim.yml

    STEP 2: CONNECT AND START THE NIM
    ----------------------------------
    aws ssm start-session --target ${aws_instance.cosmos.id} --region ${var.aws_region}

    # Inside the session:
    sudo su - ubuntu
    cd ~/cosmos-nim
    ./start_nim.sh

    # Wait for NIM to be ready (2-10 minutes)
    ./test_nim.sh

    STEP 3: ACCESS FROM LOCAL MACHINE (Port Forwarding)
    ---------------------------------------------------
    # In a new terminal:
    aws ssm start-session \
      --target ${aws_instance.cosmos.id} \
      --region ${var.aws_region} \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["8000"],"localPortNumber":["8000"]}'

    # Then access: http://localhost:8000
    curl http://localhost:8000/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{"model": "nvidia/cosmos-reason1-7b", "messages": [{"role": "user", "content": "Hello!"}]}'

    ============================================================
    HELPER SCRIPTS (after Ansible completes)
    ============================================================

    cd ~/cosmos-nim
    ./start_nim.sh         # Start the NIM container
    ./stop_nim.sh          # Stop the NIM container
    ./test_nim.sh          # Test the NIM API
    ./health_check.sh      # Check system health
    ./example_reasoning.sh # Run reasoning example

    ============================================================
  EOT
}
