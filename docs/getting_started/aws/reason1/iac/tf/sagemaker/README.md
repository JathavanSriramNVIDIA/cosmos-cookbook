# Terraform: Deploy Cosmos Reason1 NIM on Amazon SageMaker

This Terraform configuration deploys [NVIDIA Cosmos Reason1-7B](https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy) NIM from AWS Marketplace to an Amazon SageMaker real-time endpoint.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Account                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Amazon SageMaker                        │  │
│  │  ┌─────────────┐    ┌──────────────────┐    ┌──────────┐  │  │
│  │  │   Model     │───▶│ Endpoint Config  │───▶│ Endpoint │  │  │
│  │  │ (Marketplace│    │ (ml.g5.12xlarge) │    │  (REST)  │  │  │
│  │  │   Package)  │    └──────────────────┘    └──────────┘  │  │
│  │  └─────────────┘                                          │  │
│  └───────────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                      IAM Role                              │  │
│  │            (SageMaker Execution Role)                      │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.0.0 installed
3. **AWS CLI** configured with credentials
4. **AWS Marketplace Subscription** to [Cosmos Reason1-7B](https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy)

### Subscribe to the Model

1. Go to [NVIDIA Cosmos Reason-1-7B on AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy)
2. Click **"Continue to subscribe"**
3. Accept the EULA and click **"Accept Offer"**
4. Click **"Continue to configuration"**
5. Select your region and copy the **Model Package ARN**
6. Extract the package name from the ARN (the part after `model-package/`)

## Quick Start

```bash
# 1. Clone and navigate to the terraform directory
cd docs/getting_started/aws/reason1/iac/tf/sagemaker

# 2. Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# 3. Edit terraform.tfvars with your values
#    - Set nim_package to your model package name
#    - Set aws_region to your subscribed region

# 4. Initialize Terraform
terraform init

# 5. Review the deployment plan
terraform plan

# 6. Deploy the infrastructure
terraform apply
```

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `nim_package` | Model package name from AWS Marketplace subscription |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `resource_prefix` | `nim` | Prefix for resource names |
| `instance_type` | `ml.g5.12xlarge` | SageMaker instance type |
| `instance_count` | `1` | Number of endpoint instances |
| `container_startup_timeout` | `900` | Container startup timeout (seconds) |
| `tags` | `{}` | Additional resource tags |

### Recommended Instance Types

| Instance Type | GPUs | Memory | Best For | Cost/hr* |
|---------------|------|--------|----------|----------|
| `ml.g6e.xlarge` | 1x L40S | 48GB | Real-time inference | ~$1.50 |
| `ml.g5.12xlarge` | 4x A10G | 96GB | Balanced workloads | ~$7.00 |
| `ml.g5.24xlarge` | 4x A10G | 96GB | High throughput | ~$10.00 |
| `ml.p4d.24xlarge` | 8x A100 | 320GB | Maximum performance | ~$32.00 |

*Costs are approximate and vary by region. Add $1.00/hr for NIM software.

## Usage

### Test the Endpoint

After deployment, test the endpoint using Python:

```python
import boto3
import json
import base64

# Initialize client
client = boto3.client('sagemaker-runtime', region_name='us-east-1')

# Prepare payload with image
with open("your_image.jpg", "rb") as f:
    image_data = base64.b64encode(f.read()).decode("utf-8")

payload = {
    "model": "nvidia/cosmos-reason1-7b",
    "messages": [
        {
            "role": "system",
            "content": "Answer the question in the following format: <think>\nyour reasoning\n</think>\n\n<answer>\nyour answer\n</answer>."
        },
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "What is happening in this image?"},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_data}"}}
            ]
        }
    ],
    "temperature": 0.6,
    "max_tokens": 200
}

# Invoke endpoint
response = client.invoke_endpoint(
    EndpointName='nim-cosmos-reason1-endpoint',  # Use your endpoint name
    ContentType='application/json',
    Body=json.dumps(payload)
)

result = json.loads(response['Body'].read().decode())
print(result)
```

### Streaming Inference (Recommended)

For reasoning models, streaming is recommended to avoid timeout issues:

```python
import boto3
import json

client = boto3.client('sagemaker-runtime', region_name='us-east-1')

payload = {
    "model": "nvidia/cosmos-reason1-7b",
    "messages": [{"role": "user", "content": "Explain quantum computing"}],
    "max_tokens": 500,
    "stream": True  # Enable streaming
}

response = client.invoke_endpoint_with_response_stream(
    EndpointName='nim-cosmos-reason1-endpoint',
    ContentType='application/json',
    Accept='application/jsonlines',
    Body=json.dumps(payload)
)

# Process streaming response
for event in response['Body']:
    chunk = event.get('PayloadPart', {}).get('Bytes', b'')
    print(chunk.decode(), end='', flush=True)
```

## Clean Up

To destroy all resources and stop charges:

```bash
terraform destroy
```

## Troubleshooting

### Endpoint Creation Timeout

If the endpoint takes too long to create:

- Increase `container_startup_timeout` (default: 900 seconds)
- NIM containers need time to download and load model weights

### Inference Timeout

For reasoning models with long responses:

- Use **streaming inference** (`invoke_endpoint_with_response_stream`)
- Contact AWS Support to increase timeout limits if using non-streaming

### Quota Errors

If you get quota errors:

1. Go to [Service Quotas](https://console.aws.amazon.com/servicequotas/)
2. Search for "SageMaker" and your instance type
3. Request a quota increase

## Cost Estimation

| Component | Cost |
|-----------|------|
| NIM Software | $1.00/host/hour |
| ml.g5.12xlarge | ~$7.00/hour |
| **Total** | **~$8.00/hour** |

> **Tip:** Delete the endpoint when not in use to minimize costs.

## References

- [NVIDIA Cosmos Reason1-7B on AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy)
- [NVIDIA NIM Deploy Repository](https://github.com/NVIDIA/nim-deploy)
- [Official Deployment Notebook](https://github.com/NVIDIA/nim-deploy/blob/main/cloud-service-providers/aws/sagemaker/aws_marketplace_notebooks/nim_cosmos-reason1-7b_aws_marketplace.ipynb)
- [Amazon SageMaker Documentation](https://docs.aws.amazon.com/sagemaker/)
- [Cosmos Reason1 Model Card](https://build.nvidia.com/nvidia/cosmos-reason1-7b/modelcard)
