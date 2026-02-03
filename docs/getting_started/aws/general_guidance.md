# General Guidance for Cosmos on AWS: Inference and Post-Training
>
> **Author:** [Jathavan Sriram](https://www.linkedin.com/in/jathavansriram/)
> **Organization:** NVIDIA

This guide provides an overview of running NVIDIA Cosmos models on Amazon Web Services (AWS). AWS offers multiple deployment pathways, each suited to different use cases, team expertise, and operational requirements.

## Overview

Running Cosmos on AWS enables you to leverage scalable GPU infrastructure for inference, fine-tuning, and production deployments.

AWS provides several options for deploying Cosmos models:

| Deployment Option | Best For | Complexity | Scalability |
|-------------------|----------|------------|-------------|
| **Amazon SageMaker** | ML teams, managed inference, post-training | Low–Medium | High |
| **Amazon EKS** | Platform teams, containerized workloads | Medium–High | Very High |
| **Amazon EC2** | Full control, custom setups | Medium | Medium |
| **AWS Batch** | Batch processing, job scheduling | Low–Medium | High |

## Deployment Options

### Amazon SageMaker

[Amazon SageMaker](https://aws.amazon.com/sagemaker/) is a fully managed machine learning service that simplifies deploying and scaling ML models. SageMaker offers multiple ways to run Cosmos:

> **Quick Start:** [NVIDIA Cosmos Reason-1-7B](https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy) is available on AWS Marketplace as a pre-trained SageMaker model package. Deploy it on GPU instances like `ml.g5.12xlarge` or `ml.g6e.xlarge`.

#### SageMaker JumpStart

- Pre-packaged foundation models with one-click deployment
- Ideal for quick experimentation and prototyping
- Managed endpoints with auto-scaling

#### SageMaker Inference

- Real-time endpoints for low-latency inference
- Batch transform for high-throughput offline processing
- Support for custom containers and model artifacts

#### SageMaker Training

- Managed training jobs with spot instance support
- Distributed training across multiple GPUs/nodes
- Integration with SageMaker Experiments for tracking

**When to use SageMaker:**

- Teams wanting managed infrastructure
- Rapid prototyping and experimentation
- Production deployments with built-in monitoring

---

### Amazon EKS (Elastic Kubernetes Service)

[Amazon EKS](https://aws.amazon.com/eks/) provides managed Kubernetes for containerized workloads. For teams already using Kubernetes, EKS offers a familiar deployment model with GPU support.

**Key Features:**

- Native Kubernetes experience with AWS integration
- GPU operator support for NVIDIA GPUs
- Horizontal pod autoscaling for inference workloads
- Integration with AWS networking and security

**Common Patterns:**

- Deploy Cosmos using NVIDIA Triton Inference Server and NIMs
- Use Helm charts for reproducible deployments
- Leverage Karpenter for efficient GPU node scaling

**When to use EKS:**

- Teams with existing Kubernetes expertise
- Multi-model serving requirements
- Complex orchestration needs
- Hybrid/multi-cloud strategies

---

### Amazon EC2

[Amazon EC2](https://aws.amazon.com/ec2/) provides direct access to GPU instances, offering maximum flexibility for custom deployments.

**Recommended Instance Types:**

- **p5.48xlarge**: 8x NVIDIA H100 GPUs (640GB total)
- **p4d.24xlarge**: 8x NVIDIA A100 GPUs (320GB total)
- **g5.48xlarge**: 8x NVIDIA A10G GPUs (192GB total)

**When to use EC2:**

- Custom environment requirements
- Development and experimentation
- Full control over the software stack
- Cost optimization with Spot Instances

---

## Hardware Requirements

Cosmos models have varying hardware requirements depending on the model variant:

| Model | Minimum GPU Memory | Recommended Instance |
|-------|-------------------|---------------------|
| Cosmos-Reason1-7B | 24GB | g5.2xlarge, p4d.24xlarge |
| Cosmos-Transfer2-7B | 24GB | g5.2xlarge, p4d.24xlarge |
| Cosmos-Predict2-2B | 16GB | g5.xlarge |
| Cosmos-Predict2-14B | 80GB | p4d.24xlarge, p5.48xlarge |

> **Note:** For post-training (fine-tuning), requirements increase significantly. Plan for 2–4x the inference memory requirements.

## Prerequisites

Before deploying Cosmos on AWS, ensure you have:

- **AWS Account** with appropriate service quotas for GPU instances
- **IAM Permissions** for the chosen deployment method
- **Hugging Face Account** with access to [Cosmos models](https://huggingface.co/nvidia)
- **NGC Account** (optional) for accessing NVIDIA containers

### Requesting GPU Quota

GPU instances require quota increases. Request them via the [Service Quotas console](https://console.aws.amazon.com/servicequotas/):

1. Navigate to **Amazon EC2** quotas
2. Search for your desired instance type (e.g., "p5.48xlarge")
3. Request an increase (allow 24–48 hours for approval)

### Air-Gapped Environments

#### Hugging Face Model Weight Download

- You might have to set `HF_HUB_OFFLINE=1` to avoid any calls to the HuggingFace APIs. See [here](https://huggingface.co/docs/huggingface_hub/en/package_reference/environment_variables#hfhuboffline) for more details

## Cost Considerations

Running Cosmos models on GPU instances can be expensive. Consider these strategies:

- **Spot Instances**: Up to 90% savings for fault-tolerant workloads
- **Savings Plans**: Commit to consistent usage for discounts
- **Right-sizing**: Match instance type to actual requirements
- **Auto-scaling**: Scale down during low-demand periods
- **SageMaker Serverless**: Pay only for inference time

## Security Best Practices

- Store model weights in **Amazon EFS** with encryption
- Use **IAM roles** instead of access keys
- Deploy in **private subnets** with VPC endpoints
- Enable **CloudTrail** for audit logging
- Use **Secrets Manager** for API keys and tokens

## Troubleshooting

### Error: No quota bla bla

## Additional Resources

- [AWS Blog: Running NVIDIA Cosmos World Foundation Models on AWS](https://aws.amazon.com/blogs/hpc/running-nvidia-cosmos-world-foundation-models-on-aws/)
- [NVIDIA Cosmos Reason-1-7B on AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-e6loqk6jyzssy)
- [NVIDIA Cosmos on NGC](https://catalog.ngc.nvidia.com/)
- [Cosmos Cookbook](https://github.com/nvidia-cosmos/cosmos-cookbook)
- [Cosmos Reason1 GitHub Repository](https://github.com/nvidia-cosmos/cosmos-reason1)

## Support

For issues related to:

- **Cosmos Models**: Open an issue on the relevant [Cosmos GitHub repository](https://github.com/nvidia-cosmos)
- **AWS Services**: Contact [AWS Support](https://aws.amazon.com/support/)
