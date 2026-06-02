# =============================================================================
# Enterprise Data Platform — Local Development Values
# File: terraform/terraform.tfvars
# =============================================================================

platform_name           = "edp-core"
environment             = "development"
team_name               = "platform-engineering"
cost_center             = "PLAT-001"

aws_region              = "us-east-1"
localstack_mode         = true
availability_zone_count = 2

vpc_cidr                = "10.0.0.0/16"

db_instance_class        = "db.t3.medium"
db_allocated_storage     = 20
db_max_allocated_storage = 100
db_name                  = "platform_db"
db_username              = "platform_admin"
db_password              = "PlatformSecure2024!!"

redis_node_type         = "cache.t3.micro"

kafka_instance_type     = "kafka.t3.small"
kafka_volume_size       = 100

sns_alarm_topic_arn     = ""
