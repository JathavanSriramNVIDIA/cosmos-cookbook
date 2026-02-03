# Terraform: Deploy Cosmos Reason1 NIM on AWS EC2 GPU Instance

This Terraform configuration deploys a single AWS EC2 GPU instance in a **dedicated VPC** with private subnets, pre-configured for running [NVIDIA Cosmos Reason1-7B](https://build.nvidia.com/nvidia/cosmos-reason1-7b) NIM container.

**Security Features**:

- Dedicated VPC with private subnets (no public IPs on instances)
- Access via [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) - no SSH keys or open ports
- VPC endpoints for AWS services (SSM, S3)
- NAT Gateway for controlled outbound access
- VPC Flow Logs for network monitoring
- Encrypted EBS volumes
- Scoped IAM policies (no wildcard S3 access)

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                  AWS Account                                      │
│  ┌────────────────────────────────────────────────────────────────────────────┐  │
│  │                         Dedicated VPC (10.0.0.0/16)                         │  │
│  │                                                                              │  │
│  │  ┌─────────────────────────────┐   ┌─────────────────────────────────────┐  │  │
│  │  │     Public Subnet (AZ-a)    │   │       Private Subnet (AZ-a)         │  │  │
│  │  │        10.0.0.0/20          │   │          10.0.32.0/20               │  │  │
│  │  │  ┌───────────────────────┐  │   │  ┌─────────────────────────────┐   │  │  │
│  │  │  │     NAT Gateway       │  │   │  │     EC2 GPU Instance        │   │  │  │
│  │  │  │  (Outbound Internet)  │◄─┼───┼──│  • Deep Learning AMI        │   │  │  │
│  │  │  └───────────────────────┘  │   │  │  • NVIDIA Drivers           │   │  │  │
│  │  └─────────────────────────────┘   │  │  • Docker + Container Toolkit│   │  │  │
│  │                │                    │  │  • Cosmos Reason1 NIM       │   │  │  │
│  │                ▼                    │  │  • No Public IP             │   │  │  │
│  │  ┌─────────────────────────────┐   │  └─────────────────────────────┘   │  │  │
│  │  │     Internet Gateway        │   │                 ▲                   │  │  │
│  │  └─────────────────────────────┘   │                 │                   │  │  │
│  │                                     │  ┌─────────────┴───────────────┐   │  │  │
│  │                                     │  │      VPC Endpoints          │   │  │  │
│  │                                     │  │  • SSM, SSMMessages         │   │  │  │
│  │                                     │  │  • EC2Messages, S3          │   │  │  │
│  │                                     │  └─────────────────────────────┘   │  │  │
│  │                                     └─────────────────────────────────────┘  │  │
│  │                                                                              │  │
│  │  ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────────┐ │  │
│  │  │  Security Groups   │  │     IAM Role       │  │    VPC Flow Logs       │ │  │
│  │  │  • No inbound SSH  │  │  • SSM Core        │  │  • CloudWatch Logs     │ │  │
│  │  │  • Restricted egress│ │  • Scoped S3       │  │  • 30 day retention    │ │  │
│  │  └────────────────────┘  └────────────────────┘  └────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                   │
│  Access via AWS Systems Manager Session Manager (IAM-authenticated)              │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │  aws ssm start-session --target i-xxxxx --region us-east-1                  │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **AWS Account** with appropriate permissions for EC2, VPC, IAM, SSM
2. **Terraform** >= 1.0.0 installed
3. **AWS CLI v2** configured with credentials
4. **Session Manager Plugin** installed ([Installation Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html))
5. **NVIDIA NGC API Key** from [NGC Personal Keys](https://org.ngc.nvidia.com/setup/personal-keys)
6. **GPU Instance Quota** - Request quota increase if needed for your chosen instance type

### Install Session Manager Plugin

```bash
# macOS
brew install --cask session-manager-plugin

# Linux (Debian/Ubuntu)
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb

# Windows
# Download from: https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe
```

### Hardware Requirements (per NVIDIA)

From the [NVIDIA NIM Prerequisites](https://docs.nvidia.com/nim/cosmos/latest/prerequisites.html):

| Component | Requirement |
|-----------|-------------|
| GPU | NVIDIA Ampere architecture or later (A10G, L4, A100, H100) |
| CPU | x86_64 architecture |
| RAM | At least 90GB |
| Disk | At least 100GB |
| NVIDIA Driver | Version 535 or later |
| Docker | Version 23.0.1 or later |
| NVIDIA Container Toolkit | Version 1.16.2 or later |

## Quick Start

```bash
# 1. Navigate to the terraform directory
cd docs/getting_started/aws/reason1/iac/tf/ec2

# 2. Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# 3. Edit terraform.tfvars if needed (defaults work for most cases)

# 4. Initialize and deploy Terraform (creates VPC, subnets, NAT Gateway, instance)
terraform init
terraform apply

# 5. Configure software with Ansible
export NGC_API_KEY="your-ngc-api-key"
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(terraform output -raw region)

cd ansible
sed -i "s/i-xxxxxxxxxxxxxxxxx/$INSTANCE_ID/" inventory_ssm.yml
sed -i "s/us-east-1/$REGION/" inventory_ssm.yml
pip install boto3 botocore ansible

# Wait for instance to be ready (~2 minutes)
sleep 120
ansible-playbook -i inventory_ssm.yml setup_cosmos_nim.yml

# 6. Connect and start the NIM
aws ssm start-session --target $INSTANCE_ID --region $REGION
# Inside session:
sudo su - ubuntu
cd ~/cosmos-nim
./start_nim.sh
```

## Configuration

### Required Variables

None! The defaults work for most cases.

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `resource_prefix` | `nim` | Prefix for resource names |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the dedicated VPC |
| `instance_type` | `g5.12xlarge` | EC2 GPU instance type |
| `root_volume_size` | `200` | Root volume size in GB |
| `kms_key_arn` | `null` | KMS key ARN for EBS encryption |
| `enable_vpc_flow_logs` | `true` | Enable VPC flow logs for monitoring |
| `allowed_api_cidrs` | `[]` | CIDRs for direct API access (use SSM port forwarding instead) |
| `s3_bucket_arns` | `null` | Specific S3 bucket ARNs to allow access |

### Recommended Instance Types

| Instance Type | GPUs | GPU Memory | RAM | Cost/hr* |
|---------------|------|------------|-----|----------|
| `g5.12xlarge` | 4x A10G | 96GB | 192GB | ~$5.67 |
| `g5.24xlarge` | 4x A10G | 96GB | 384GB | ~$8.14 |
| `g5.48xlarge` | 8x A10G | 192GB | 768GB | ~$16.29 |
| `g6.12xlarge` | 4x L4 | 192GB | 192GB | ~$5.50 |
| `p4d.24xlarge` | 8x A100 | 320GB | 1152GB | ~$32.77 |

*Costs are approximate on-demand pricing and vary by region. Add NAT Gateway costs (~$0.045/hr + data transfer).

## Deployment Steps

### Step 1: Deploy Infrastructure with Terraform

```bash
cd docs/getting_started/aws/reason1/iac/tf/ec2

# Initialize
terraform init

# Plan
terraform plan -out=plan.out

# Apply (creates VPC, subnets, NAT Gateway, VPC endpoints, instance)
terraform apply plan.out

# Note the outputs
terraform output
```

This creates:

- Dedicated VPC with public and private subnets
- Internet Gateway and NAT Gateway
- VPC endpoints for SSM, SSMMessages, EC2Messages, S3
- Security groups with restricted rules
- EC2 GPU instance in private subnet
- VPC Flow Logs (if enabled)

### Step 2: Configure Software with Ansible

Ansible handles all software configuration including:

- Docker installation and configuration
- NVIDIA Container Toolkit setup
- NGC authentication
- NIM container image pull
- Helper script creation

```bash
# Install Ansible requirements
pip install boto3 botocore ansible

# Set your NGC API key
export NGC_API_KEY="your-ngc-api-key"

# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(terraform output -raw region)

# Get the S3 bucket name for Ansible file transfers
BUCKET=$(terraform output -raw ansible_s3_bucket)

# Update the Ansible inventory with instance ID, region, and bucket
cd ansible
sed -i "s/i-xxxxxxxxxxxxxxxxx/$INSTANCE_ID/" inventory_ssm.yml
sed -i "s/us-east-1/$REGION/" inventory_ssm.yml
sed -i "s/ANSIBLE_BUCKET_NAME/$BUCKET/" inventory_ssm.yml

# Wait for SSM agent to register (1-2 minutes after instance launch)
sleep 120

# Run the playbook
ansible-playbook -i inventory_ssm.yml setup_cosmos_nim.yml
```

### Step 3: Connect and Start the NIM

```bash
# Connect via Session Manager
aws ssm start-session --target $INSTANCE_ID --region $REGION

# Switch to ubuntu user and start NIM
sudo su - ubuntu
cd ~/cosmos-nim
./start_nim.sh

# Wait for startup (2-10 minutes depending on GPU)
# The script will notify when ready
```

### Step 4: Access the NIM API

#### Option A: From the Instance (via Session Manager)

```bash
# Test health
curl http://localhost:8000/v1/health/ready

# Test inference
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "nvidia/cosmos-reason1-7b", "messages": [{"role": "user", "content": "What is a robot?"}]}'
```

#### Option B: From Your Local Machine (via Port Forwarding)

```bash
# In a new terminal, start port forwarding
INSTANCE_ID=$(terraform output -raw instance_id)
REGION=$(terraform output -raw region)

aws ssm start-session \
  --target $INSTANCE_ID \
  --region $REGION \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8000"],"localPortNumber":["8000"]}'

# Now in another terminal, access the API via localhost
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "nvidia/cosmos-reason1-7b", "messages": [{"role": "user", "content": "Hello!"}]}'
```

## Usage Examples

### Basic Text Inference

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/cosmos-reason1-7b",
    "messages": [
      {"role": "user", "content": "What is a robot?"}
    ],
    "max_tokens": 150,
    "temperature": 0.6
  }'
```

### Reasoning Mode (Chain-of-Thought)

```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/cosmos-reason1-7b",
    "messages": [
      {
        "role": "system",
        "content": "Answer the question in the following format: <think>\nyour reasoning\n</think>\n\n<answer>\nyour answer\n</answer>."
      },
      {
        "role": "user",
        "content": "If a robot needs to pick up a cup, what must it consider?"
      }
    ],
    "max_tokens": 500,
    "temperature": 0.6
  }'
```

### Multimodal Inference (Image + Text)

```bash
# Encode image to base64
IMAGE_BASE64=$(base64 -w0 your_image.jpg)

curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"nvidia/cosmos-reason1-7b\",
    \"messages\": [
      {
        \"role\": \"user\",
        \"content\": [
          {\"type\": \"text\", \"text\": \"Describe what you see.\"},
          {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/jpeg;base64,${IMAGE_BASE64}\"}}
        ]
      }
    ],
    \"max_tokens\": 300
  }"
```

### Python Client Example

```python
import requests
import base64

# API endpoint (via SSM port forwarding)
url = "http://localhost:8000/v1/chat/completions"

# With image
with open("image.jpg", "rb") as f:
    image_b64 = base64.b64encode(f.read()).decode()

payload = {
    "model": "nvidia/cosmos-reason1-7b",
    "messages": [
        {
            "role": "system",
            "content": "Answer in the format: <think>reasoning</think><answer>answer</answer>"
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "What is happening in this image?"},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}}
            ]
        }
    ],
    "max_tokens": 300,
    "temperature": 0.6
}

response = requests.post(url, json=payload)
print(response.json())
```

## Ansible Playbook Details

The Ansible playbook (`ansible/setup_cosmos_nim.yml`) is the **required** method for software configuration. It provides:

### Phases

1. **System Prerequisites** - Updates, essential packages
2. **NVIDIA Driver Verification** - Validates driver version >= 535
3. **Docker Installation** - Full Docker CE installation
4. **NVIDIA Container Toolkit** - GPU support for containers
5. **Docker GPU Verification** - Tests GPU access in containers
6. **NGC Authentication** - Logs into NVIDIA container registry
7. **Workspace Setup** - Creates working directory and credentials
8. **NIM Image Pull** - Downloads the Cosmos Reason1 container
9. **Helper Scripts** - Creates convenience scripts
10. **Summary** - Displays configuration status

### Re-running the Playbook

The playbook is idempotent and can be safely re-run:

```bash
cd ansible
ansible-playbook -i inventory_ssm.yml setup_cosmos_nim.yml
```

### Customization

Edit variables in `inventory_ssm.yml` or pass them via command line:

```bash
ansible-playbook -i inventory_ssm.yml setup_cosmos_nim.yml \
  -e "nim_image=nvcr.io/nim/nvidia/cosmos-reason1-7b:v1.0.0" \
  -e "nim_port=8080"
```

## Monitoring & Troubleshooting

### Check GPU Status (via Session Manager)

```bash
aws ssm start-session --target $INSTANCE_ID
# Then run:
nvidia-smi
```

### Check Container Logs

```bash
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker logs --tail 50 cosmos-reason1"]' \
  --output text
```

### Check VPC Flow Logs

```bash
# View flow logs in CloudWatch
aws logs filter-log-events \
  --log-group-name "/aws/vpc/${RESOURCE_PREFIX}-cosmos-flow-logs" \
  --limit 20
```

### Health Check

```bash
# Via port forwarding
curl http://localhost:8000/v1/health/ready
```

### Common Issues

| Issue | Solution |
|-------|----------|
| SSM connection fails | Wait 2-3 minutes for SSM agent to register via VPC endpoints |
| "Target not connected" | Check VPC endpoints are created and instance has route to them |
| Docker GPU not working | Run Ansible playbook or check user-data logs |
| NIM container won't start | Check NGC_API_KEY is valid with NIM access |
| Out of GPU memory | Use larger instance type (more GPUs) |
| Slow inference | Normal for first request (model loading) |

### Check SSM Agent Status

```bash
# From AWS CLI
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query "InstanceInformationList[0].PingStatus"
```

## Security Features

| Feature | Implementation |
|---------|----------------|
| **Dedicated VPC** | Isolated network, not using default VPC |
| **Private Subnets** | Instance has no public IP |
| **No SSH** | Session Manager used - no port 22 exposure |
| **VPC Endpoints** | AWS API calls stay within AWS network |
| **NAT Gateway** | Controlled outbound internet access |
| **Restricted Egress** | Only HTTPS, HTTP, DNS allowed outbound |
| **VPC Flow Logs** | Network traffic monitoring |
| **IMDSv2 Required** | Prevents SSRF attacks |
| **EBS Encryption** | Root volume encrypted (optional CMK) |
| **Scoped IAM** | S3 access only to specified buckets |
| **Audit Trail** | All SSM sessions logged in CloudTrail |

## Clean Up

To destroy all resources and stop charges:

```bash
# Stop the NIM container first (optional)
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["docker stop cosmos-reason1"]'

# Destroy infrastructure (VPC, subnets, NAT Gateway, instance, etc.)
terraform destroy
```

## Cost Estimation

| Component | Cost |
|-----------|------|
| g5.12xlarge instance | ~$5.67/hour |
| NAT Gateway | ~$0.045/hour + data transfer |
| 200GB gp3 EBS | ~$16/month |
| VPC Endpoints (3 interface) | ~$0.01/hour each |
| VPC Flow Logs | ~$0.50/GB ingested |

**Tip:** Stop the instance when not in use to save costs. NAT Gateway charges continue while VPC exists.

## File Structure

```
ec2/
├── main.tf                 # Main Terraform configuration (VPC, subnets, instance)
├── variables.tf            # Variable definitions
├── outputs.tf              # Output definitions
├── terraform.tfvars.example # Example configuration
├── README.md               # This file
├── .gitignore              # Git ignore patterns
├── ansible/
│   ├── inventory_ssm.yml   # Ansible inventory for SSM connection
│   ├── requirements.txt    # Ansible Python dependencies
│   └── setup_cosmos_nim.yml # Main Ansible playbook
└── examples/
    ├── reason1_ec2_example.py  # Python example script
    └── requirements.txt        # Python dependencies
```

## References

- [NVIDIA NIM Prerequisites](https://docs.nvidia.com/nim/cosmos/latest/prerequisites.html)
- [NVIDIA NIM Quickstart](https://docs.nvidia.com/nim/cosmos/latest/quickstart.html)
- [Cosmos Reason1 Model Card](https://build.nvidia.com/nvidia/cosmos-reason1-7b/modelcard)
- [AWS Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Session Manager Plugin Installation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- [VPC Endpoints for Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-privatelink.html)
- [NGC Container Registry](https://catalog.ngc.nvidia.com/)
- [AWS Deep Learning AMIs](https://aws.amazon.com/machine-learning/amis/)
