variable "key_name" {
  description = "The key name to use for the instance"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where the instance will be created"
  type        = string
}

# The variables below may not necessarily need to be changed

variable "same_region_benchmark_region" {
  description = "AWS region for the EC2 instance running benchmarking and the two S3 buckets that will be used for same-region benchmarking."
  type        = string
  default     = "us-east-1"
}

variable "other_region_benchmark_region" {
  description = "AWS region for the S3 bucket that will be used for other-region benchmarking."
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "c7gn.16xlarge"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instance"
  type        = string
  default     = "ami-08b46fd32a1a5be7f"
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile for AWS CLI access"
  type        = string
  default     = "benchmarking-instance-profile"
}

variable "policy_name" {
  description = "Name of the IAM policy for AWS CLI commands"
  type        = string
  default     = "benchmarking-ec2-policy"
}
