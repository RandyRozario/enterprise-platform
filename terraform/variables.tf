# =============================================================================
# Enterprise Data Platform Core — Terraform Variables
# File: terraform/variables.tf
# =============================================================================

# =============================================================================
# PLATFORM IDENTITY
# =============================================================================

variable "platform_name" {
  description = "Base name for all platform resources"
  type        = string
  default     = "edp-core"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.platform_name))
    error_message = "Platform name must be 3-20 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "team_name" {
  description = "Owning team name for resource tagging"
  type        = string
  default     = "platform-engineering"
}

variable "cost_center" {
  description = "Cost center code for FinOps attribution"
  type        = string
  default     = "PLAT-001"
}

# =============================================================================
# AWS / LOCALSTACK CONFIGURATION
# =============================================================================

variable "aws_region" {
  description = "AWS region for resource provisioning"
  type        = string
  default     = "us-east-1"
}

variable "aws_access_key" {
  description = "AWS access key (leave empty when using instance profiles)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key (leave empty when using instance profiles)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "localstack_mode" {
  description = "Set to true for LocalStack local simulation (zero cost)"
  type        = bool
  default     = true
}

variable "availability_zone_count" {
  description = "Number of availability zones to deploy across"
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 3
    error_message = "AZ count must be between 1 and 3."
  }
}

# =============================================================================
# NETWORKING
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# =============================================================================
# DATABASE (RDS POSTGRESQL)
# =============================================================================

variable "db_instance_class" {
  description = "RDS instance type"
  type        = string
  default     = "db.t3.medium"
}

variable "db_allocated_storage" {
  description = "Initial RDS storage in GB"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum RDS storage for autoscaling in GB"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "platform_db"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "platform_admin"
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 16
    error_message = "Database password must be at least 16 characters."
  }
}

# =============================================================================
# CACHE (ELASTICACHE REDIS)
# =============================================================================

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

# =============================================================================
# STREAMING (MSK KAFKA)
# =============================================================================

variable "kafka_instance_type" {
  description = "MSK Kafka broker instance type"
  type        = string
  default     = "kafka.t3.small"
}

variable "kafka_volume_size" {
  description = "Kafka broker EBS volume size in GB"
  type        = number
  default     = 100
}

# =============================================================================
# ALERTING
# =============================================================================

variable "sns_alarm_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications (empty to disable)"
  type        = string
  default     = ""
}
