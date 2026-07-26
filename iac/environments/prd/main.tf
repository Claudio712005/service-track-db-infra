locals {
  project     = "servicetrack"
  environment = "prd"
  name        = "${local.project}-${local.environment}"
}

# A rede pertence ao repositorio de infraestrutura e e aplicada antes deste
# state. Ler daqui e o que quebra a dependencia circular: o banco entra numa
# VPC existente em vez de exigir que a infraestrutura conheca o banco.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "servicetrack/${local.environment}-network/terraform.tfstate"
    region = var.region
  }
}

module "rds" {
  source = "../../modules/rds"

  name       = local.name
  ssm_prefix = "${local.project}/${local.environment}"

  tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = "service-track-db-infra"
  }

  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  db_name                   = "servicetrack"
  db_username               = "servicetrack"
  db_engine_version         = "16.4"
  db_parameter_group_family = "postgres16"

  db_instance_class        = "db.t3.medium"
  db_allocated_storage     = 50
  db_max_allocated_storage = 200
  db_multi_az              = true
  db_backup_retention_days = 7

  db_max_connections                = 300
  db_idle_in_transaction_timeout_ms = 60000
  db_log_min_duration_ms            = 1000

  pool_api_max_size           = 15
  pool_api_migration_max_size = 2
  pool_lambda_max_size        = 2
  app_replicas_max            = 10
  lambda_concurrency_estimate = 20
}
