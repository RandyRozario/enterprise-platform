# =============================================================================
# Enterprise Data Platform Core — Terraform Infrastructure
# File: terraform/main.tf
# =============================================================================
# Provisions a complete multi-tier local simulation environment using
# LocalStack (AWS emulation) with:
#   - VPC with isolated subnets per tier (streaming / database / cache)
#   - Security groups with strict ingress/egress rules
#   - ECS cluster for container orchestration
#   - RDS PostgreSQL (multi-tenant SaaS database)
#   - ElastiCache Redis (session/cache layer)
#   - MSK Kafka (streaming pipeline)
#   - S3 buckets (data lake, SBOM artifacts, audit logs)
#   - CloudWatch log groups and metric alarms
#   - IAM roles and policies (least-privilege)
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state for development — switch to S3 backend for production
  backend "local" {
    path = "terraform.tfstate"
  }
}

# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================
# Points to LocalStack for zero-cost local simulation.
# Remove endpoint overrides and set real region for cloud deployment.

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.localstack_mode ? "mock_access_key"    : var.aws_access_key
  secret_key                  = var.localstack_mode ? "mock_secret_key"    : var.aws_secret_key
  skip_credentials_validation = var.localstack_mode
  skip_metadata_api_check     = var.localstack_mode
  skip_requesting_account_id  = var.localstack_mode

  dynamic "endpoints" {
    for_each = var.localstack_mode ? [1] : []
    content {
      ec2            = "http://localhost:4566"
      ecs            = "http://localhost:4566"
      rds            = "http://localhost:4566"
      elasticache    = "http://localhost:4566"
      kafka          = "http://localhost:4566"
      s3             = "http://localhost:4566"
      iam            = "http://localhost:4566"
      cloudwatch     = "http://localhost:4566"
      logs           = "http://localhost:4566"
      secretsmanager = "http://localhost:4566"
      sns            = "http://localhost:4566"
      sqs            = "http://localhost:4566"
      route53        = "http://localhost:4566"
      lambda         = "http://localhost:4566"
    }
  }
}

provider "random" {}

# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# RANDOM SUFFIXES FOR UNIQUE RESOURCE NAMES
# =============================================================================

resource "random_id" "platform" {
  byte_length = 4
}

locals {
  platform_name = "${var.platform_name}-${random_id.platform.hex}"
  common_tags = {
    Platform    = var.platform_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.team_name
    CostCenter  = var.cost_center
    CreatedAt   = timestamp()
  }
}

# =============================================================================
# VPC — PLATFORM NETWORK FOUNDATION
# =============================================================================

resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-igw"
  })
}

# =============================================================================
# SUBNETS — THREE-TIER ISOLATION
# =============================================================================

# ── Tier 1: Public Subnets (Load Balancers, NAT Gateways) ────────────────────
resource "aws_subnet" "public" {
  count             = var.availability_zone_count
  vpc_id            = aws_vpc.platform.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-public-${count.index + 1}"
    Tier = "public"
  })
}

# ── Tier 2: Application Subnets (Streaming / API Services) ───────────────────
resource "aws_subnet" "application" {
  count             = var.availability_zone_count
  vpc_id            = aws_vpc.platform.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-app-${count.index + 1}"
    Tier = "application"
  })
}

# ── Tier 3: Data Subnets (PostgreSQL, Redis, Kafka) ──────────────────────────
resource "aws_subnet" "data" {
  count             = var.availability_zone_count
  vpc_id            = aws_vpc.platform.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-data-${count.index + 1}"
    Tier = "data"
  })
}

# ── Tier 4: Cache Subnets (Redis Cluster) ────────────────────────────────────
resource "aws_subnet" "cache" {
  count             = var.availability_zone_count
  vpc_id            = aws_vpc.platform.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 30)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-cache-${count.index + 1}"
    Tier = "cache"
  })
}

# =============================================================================
# NAT GATEWAYS (one per AZ for HA)
# =============================================================================

resource "aws_eip" "nat" {
  count  = var.availability_zone_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "platform" {
  count         = var.availability_zone_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.platform]

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-nat-${count.index + 1}"
  })
}

# =============================================================================
# ROUTE TABLES
# =============================================================================

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.platform.id
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = var.availability_zone_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Application route tables (per-AZ for HA)
resource "aws_route_table" "application" {
  count  = var.availability_zone_count
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.platform[count.index].id
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-rt-app-${count.index + 1}" })
}

resource "aws_route_table_association" "application" {
  count          = var.availability_zone_count
  subnet_id      = aws_subnet.application[count.index].id
  route_table_id = aws_route_table.application[count.index].id
}

# Data route tables (no internet access — isolated)
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.platform.id

  tags = merge(local.common_tags, { Name = "${local.platform_name}-rt-data" })
}

resource "aws_route_table_association" "data" {
  count          = var.availability_zone_count
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

resource "aws_route_table" "cache" {
  vpc_id = aws_vpc.platform.id

  tags = merge(local.common_tags, { Name = "${local.platform_name}-rt-cache" })
}

resource "aws_route_table_association" "cache" {
  count          = var.availability_zone_count
  subnet_id      = aws_subnet.cache[count.index].id
  route_table_id = aws_route_table.cache.id
}

# =============================================================================
# SECURITY GROUPS — STRICT LEAST-PRIVILEGE
# =============================================================================

# ── ALB Security Group ────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${local.platform_name}-sg-alb"
  description = "Load balancer — HTTP/HTTPS inbound from internet"
  vpc_id      = aws_vpc.platform.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound to application tier"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-sg-alb" })
}

# ── API / Application Services Security Group ─────────────────────────────────
resource "aws_security_group" "application" {
  name        = "${local.platform_name}-sg-app"
  description = "Application services — inbound from ALB only"
  vpc_id      = aws_vpc.platform.id

  ingress {
    description     = "From ALB only"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "NestJS API port from ALB"
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Internal service mesh"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-sg-app" })
}

# ── PostgreSQL Security Group ─────────────────────────────────────────────────
resource "aws_security_group" "postgres" {
  name        = "${local.platform_name}-sg-postgres"
  description = "PostgreSQL — inbound from application tier only"
  vpc_id      = aws_vpc.platform.id

  ingress {
    description     = "PostgreSQL from application tier"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }

  egress {
    description = "No outbound from database"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-sg-postgres" })
}

# ── Redis Security Group ──────────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "${local.platform_name}-sg-redis"
  description = "Redis — inbound from application tier only"
  vpc_id      = aws_vpc.platform.id

  ingress {
    description     = "Redis from application tier"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }

  egress {
    description = "No outbound from cache"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-sg-redis" })
}

# ── Kafka Security Group ──────────────────────────────────────────────────────
resource "aws_security_group" "kafka" {
  name        = "${local.platform_name}-sg-kafka"
  description = "Kafka MSK — inbound from application tier only"
  vpc_id      = aws_vpc.platform.id

  ingress {
    description     = "Kafka broker from application"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }

  ingress {
    description     = "Kafka TLS broker from application"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }

  ingress {
    description     = "ZooKeeper from Kafka cluster"
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    self            = true
  }

  egress {
    description = "Internal only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-sg-kafka" })
}

# =============================================================================
# SECRETS MANAGER
# =============================================================================

resource "aws_secretsmanager_secret" "postgres_credentials" {
  name                    = "${local.platform_name}/postgres/credentials"
  description             = "PostgreSQL master credentials for multi-tenant platform"
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "postgres_credentials" {
  secret_id = aws_secretsmanager_secret.postgres_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    host     = aws_db_instance.platform_postgres.address
    port     = 5432
    dbname   = var.db_name
    url      = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.platform_postgres.address}:5432/${var.db_name}"
  })
}

# =============================================================================
# RDS POSTGRESQL — MULTI-TENANT DATABASE
# =============================================================================

resource "aws_db_subnet_group" "platform" {
  name       = "${local.platform_name}-db-subnet-group"
  subnet_ids = aws_subnet.data[*].id

  tags = merge(local.common_tags, { Name = "${local.platform_name}-db-subnet-group" })
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${local.platform_name}-pg16"
  family = "postgres16"

  # Enable Row-Level Security support
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Connection pooling optimization
  parameter {
    name  = "max_connections"
    value = "500"
  }

  # Performance tuning
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "work_mem"
    value = "16384"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "524288"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = local.common_tags
}

resource "aws_db_instance" "platform_postgres" {
  identifier = "${local.platform_name}-postgres"

  # Engine
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Credentials
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.platform.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = false
  port                   = 5432

  # Parameter group
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Availability
  multi_az               = var.environment == "production"
  availability_zone      = var.environment == "production" ? null : data.aws_availability_zones.available.names[0]

  # Backup
  backup_retention_period   = var.environment == "production" ? 30 : 7
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  delete_automated_backups  = var.environment != "production"
  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${local.platform_name}-final-snapshot" : null

  # Performance Insights
  performance_insights_enabled          = var.environment == "production"
  performance_insights_retention_period = var.environment == "production" ? 731 : 7

  # Enhanced monitoring
  monitoring_interval = var.environment == "production" ? 60 : 0
  monitoring_role_arn = var.environment == "production" ? aws_iam_role.rds_monitoring[0].arn : null

  # Deletion protection
  deletion_protection = var.environment == "production"

  tags = merge(local.common_tags, {
    Name        = "${local.platform_name}-postgres"
    BackupClass = "critical"
  })
}

# RDS monitoring role (production only)
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment == "production" ? 1 : 0
  name  = "${local.platform_name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"]
  tags                = local.common_tags
}

# =============================================================================
# ELASTICACHE REDIS — SESSION & CACHE LAYER
# =============================================================================

resource "aws_elasticache_subnet_group" "platform" {
  name       = "${local.platform_name}-cache-subnet"
  subnet_ids = aws_subnet.cache[*].id

  tags = local.common_tags
}

resource "aws_elasticache_parameter_group" "redis7" {
  name   = "${local.platform_name}-redis7"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  parameter {
    name  = "activedefrag"
    value = "yes"
  }

  tags = local.common_tags
}

resource "aws_elasticache_replication_group" "platform" {
  replication_group_id = "${local.platform_name}-redis"
  description          = "Platform cache and session store"

  node_type            = var.redis_node_type
  num_cache_clusters   = var.environment == "production" ? 3 : 1
  port                 = 6379

  parameter_group_name = aws_elasticache_parameter_group.redis7.name
  subnet_group_name    = aws_elasticache_subnet_group.platform.name
  security_group_ids   = [aws_security_group.redis.id]

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  # Failover
  automatic_failover_enabled = var.environment == "production"
  multi_az_enabled           = var.environment == "production"

  # Maintenance
  maintenance_window       = "tue:05:00-tue:06:00"
  snapshot_window          = "04:00-05:00"
  snapshot_retention_limit = var.environment == "production" ? 7 : 1

  apply_immediately = var.environment != "production"

  tags = merge(local.common_tags, {
    Name = "${local.platform_name}-redis"
  })
}

# =============================================================================
# MSK KAFKA — STREAMING PIPELINE
# =============================================================================

resource "aws_msk_configuration" "platform" {
  kafka_versions = ["3.6.0"]
  name           = "${local.platform_name}-kafka-config"

  server_properties = <<-PROPERTIES
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.io.threads=8
    num.network.threads=5
    num.partitions=12
    num.replica.fetchers=2
    replica.lag.time.max.ms=30000
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    socket.send.buffer.bytes=102400
    unclean.leader.election.enable=false
    zookeeper.session.timeout.ms=18000
    log.retention.hours=168
    log.segment.bytes=1073741824
    log.retention.check.interval.ms=300000
    message.max.bytes=1048588
    offsets.topic.replication.factor=3
    transaction.state.log.min.isr=2
    transaction.state.log.replication.factor=3
  PROPERTIES
}

resource "aws_msk_cluster" "platform" {
  cluster_name           = "${local.platform_name}-kafka"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = var.environment == "production" ? 3 : 1

  broker_node_group_info {
    instance_type   = var.kafka_instance_type
    client_subnets  = var.environment == "production" ? aws_subnet.data[*].id : [aws_subnet.data[0].id]
    security_groups = [aws_security_group.kafka.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.kafka_volume_size
        provisioned_throughput {
          enabled           = var.environment == "production"
          volume_throughput = var.environment == "production" ? 250 : 0
        }
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.platform.arn
    revision = aws_msk_configuration.platform.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
    encryption_at_rest_kms_key_arn = aws_kms_key.platform.arn
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.kafka.name
      }
    }
  }

  tags = merge(local.common_tags, { Name = "${local.platform_name}-kafka" })
}

# =============================================================================
# KMS ENCRYPTION KEY
# =============================================================================

resource "aws_kms_key" "platform" {
  description             = "Platform data encryption key"
  deletion_window_in_days = var.environment == "production" ? 30 : 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, { Name = "${local.platform_name}-kms" })
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${local.platform_name}"
  target_key_id = aws_kms_key.platform.key_id
}

# =============================================================================
# S3 BUCKETS — DATA LAKE, SBOM, AUDIT
# =============================================================================

resource "aws_s3_bucket" "data_lake" {
  bucket        = "${local.platform_name}-data-lake"
  force_destroy = var.environment != "production"

  tags = merge(local.common_tags, {
    Name        = "${local.platform_name}-data-lake"
    DataClass   = "sensitive"
    BackupClass = "critical"
  })
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 2555  # 7 years for compliance
    }
  }
}

resource "aws_s3_bucket" "sbom_artifacts" {
  bucket        = "${local.platform_name}-sbom-artifacts"
  force_destroy = var.environment != "production"

  tags = merge(local.common_tags, { Name = "${local.platform_name}-sbom" })
}

resource "aws_s3_bucket_versioning" "sbom_artifacts" {
  bucket = aws_s3_bucket.sbom_artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "sbom_artifacts" {
  bucket                  = aws_s3_bucket.sbom_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "audit_logs" {
  bucket        = "${local.platform_name}-audit-logs"
  force_destroy = false  # Never force-destroy audit logs

  tags = merge(local.common_tags, {
    Name        = "${local.platform_name}-audit"
    DataClass   = "compliance"
    BackupClass = "critical"
  })
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.platform.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket                  = aws_s3_bucket.audit_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Object Lock for WORM compliance (audit logs)
resource "aws_s3_bucket_object_lock_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = 7
    }
  }
}

# =============================================================================
# ECS CLUSTER — CONTAINER ORCHESTRATION
# =============================================================================

resource "aws_ecs_cluster" "platform" {
  name = "${local.platform_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "platform" {
  cluster_name = aws_ecs_cluster.platform.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.environment == "production" ? "FARGATE" : "FARGATE_SPOT"
    weight            = 1
    base              = var.environment == "production" ? 2 : 0
  }
}

# =============================================================================
# CLOUDWATCH — MONITORING AND ALARMS
# =============================================================================

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/platform/${local.platform_name}"
  retention_in_days = var.environment == "production" ? 365 : 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "kafka" {
  name              = "/platform/${local.platform_name}/kafka"
  retention_in_days = var.environment == "production" ? 90 : 7

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.platform_name}"
  retention_in_days = var.environment == "production" ? 90 : 14

  tags = local.common_tags
}

# RDS CPU alarm
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.platform_name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU utilization exceeds 80% — consider scaling"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.platform_postgres.identifier
  }

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
  ok_actions    = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []

  tags = local.common_tags
}

# RDS storage alarm
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.platform_name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120  # 5GB in bytes
  alarm_description   = "RDS free storage below 5GB"
  treat_missing_data  = "breaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.platform_postgres.identifier
  }

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
  tags          = local.common_tags
}

# Redis memory alarm
resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${local.platform_name}-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory utilization exceeds 80%"
  treat_missing_data  = "breaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.platform.id
  }

  alarm_actions = var.sns_alarm_topic_arn != "" ? [var.sns_alarm_topic_arn] : []
  tags          = local.common_tags
}

# =============================================================================
# IAM — LEAST-PRIVILEGE ROLES
# =============================================================================

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.platform_name}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]

  tags = local.common_tags
}

# ECS Task Role (application permissions)
resource "aws_iam_role" "ecs_task" {
  name = "${local.platform_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.platform_name}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.postgres_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/*",
          aws_s3_bucket.sbom_artifacts.arn,
          "${aws_s3_bucket.sbom_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.audit_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.platform.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic"
        ]
        Resource = aws_msk_cluster.platform.arn
      }
    ]
  })
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "Platform VPC ID"
  value       = aws_vpc.platform.id
}

output "postgres_endpoint" {
  description = "PostgreSQL RDS endpoint"
  value       = aws_db_instance.platform_postgres.address
  sensitive   = false
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string (sensitive)"
  value       = "postgresql://${var.db_username}:${var.db_password}@${aws_db_instance.platform_postgres.address}:5432/${var.db_name}"
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.platform.primary_endpoint_address
}

output "kafka_bootstrap_brokers" {
  description = "Kafka MSK bootstrap brokers (TLS)"
  value       = aws_msk_cluster.platform.bootstrap_brokers_tls
}

output "data_lake_bucket" {
  description = "Data lake S3 bucket name"
  value       = aws_s3_bucket.data_lake.bucket
}

output "sbom_bucket" {
  description = "SBOM artifacts S3 bucket name"
  value       = aws_s3_bucket.sbom_artifacts.bucket
}

output "audit_bucket" {
  description = "Audit logs S3 bucket name"
  value       = aws_s3_bucket.audit_logs.bucket
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.platform.name
}

output "kms_key_arn" {
  description = "Platform KMS key ARN"
  value       = aws_kms_key.platform.arn
}

output "platform_name" {
  description = "Generated platform name with random suffix"
  value       = local.platform_name
}
