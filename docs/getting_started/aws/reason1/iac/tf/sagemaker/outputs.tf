# =============================================================================
# Outputs for Cosmos Reason1 NIM Deployment
# =============================================================================

output "endpoint_name" {
  description = "Name of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.cosmos_reason1.name
}

output "endpoint_arn" {
  description = "ARN of the SageMaker endpoint"
  value       = aws_sagemaker_endpoint.cosmos_reason1.arn
}

output "model_name" {
  description = "Name of the SageMaker model"
  value       = aws_sagemaker_model.cosmos_reason1.name
}

output "execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "instance_type" {
  description = "Instance type used for the endpoint"
  value       = var.instance_type
}


output "example_script_command" {
  description = "Command to run the endpoint examples"
  value       = <<-EOT
    # Run all examples:
    python ../../examples/reason1_example.py \
      --region ${var.aws_region} \
      --endpoint-name ${aws_sagemaker_endpoint.cosmos_reason1.name}

    # Run specific example (health, basic, streaming, reasoning, multimodal):
    python ../../examples/reason1_example.py \
      --region ${var.aws_region} \
      --endpoint-name ${aws_sagemaker_endpoint.cosmos_reason1.name} \
      --test streaming
  EOT
}
