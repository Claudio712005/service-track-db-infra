resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds-sg"
  description = "PostgreSQL access from allowed security groups only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-rds-sg" })
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.rds.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-postgres-params"
  family      = var.db_parameter_group_family
  description = "Limites de conexao e diagnostico do PostgreSQL do ${var.name}"

  parameter {
    name         = "max_connections"
    value        = tostring(var.db_max_connections)
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = tostring(var.db_idle_in_transaction_timeout_ms)
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.db_log_min_duration_ms)
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier              = "${var.name}-postgres"
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  max_allocated_storage   = var.db_max_allocated_storage
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  parameter_group_name    = aws_db_parameter_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_days
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = var.tags
}

resource "aws_ssm_parameter" "endpoint" {
  name  = "/${var.ssm_prefix}/db/endpoint"
  type  = "String"
  value = aws_db_instance.this.address
  tags  = var.tags
}

resource "aws_ssm_parameter" "port" {
  name  = "/${var.ssm_prefix}/db/port"
  type  = "String"
  value = tostring(aws_db_instance.this.port)
  tags  = var.tags
}

resource "aws_ssm_parameter" "name" {
  name  = "/${var.ssm_prefix}/db/name"
  type  = "String"
  value = var.db_name
  tags  = var.tags
}

resource "aws_ssm_parameter" "username" {
  name  = "/${var.ssm_prefix}/db/username"
  type  = "String"
  value = var.db_username
  tags  = var.tags
}

resource "aws_ssm_parameter" "password" {
  name  = "/${var.ssm_prefix}/db/password"
  type  = "SecureString"
  value = random_password.db.result
  tags  = var.tags
}

resource "aws_ssm_parameter" "jdbc_url" {
  name  = "/${var.ssm_prefix}/db/jdbc-url"
  type  = "String"
  value = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
  tags  = var.tags
}

resource "aws_ssm_parameter" "security_group_id" {
  name  = "/${var.ssm_prefix}/db/security-group-id"
  type  = "String"
  value = aws_security_group.rds.id
  tags  = var.tags
}

resource "aws_ssm_parameter" "max_connections" {
  name  = "/${var.ssm_prefix}/db/max-connections"
  type  = "String"
  value = tostring(var.db_max_connections)
  tags  = var.tags
}

resource "aws_ssm_parameter" "pool_api_max_size" {
  name  = "/${var.ssm_prefix}/db/pool/api-max-size"
  type  = "String"
  value = tostring(var.pool_api_max_size)
  tags  = var.tags
}

resource "aws_ssm_parameter" "pool_api_migration_max_size" {
  name  = "/${var.ssm_prefix}/db/pool/api-migration-max-size"
  type  = "String"
  value = tostring(var.pool_api_migration_max_size)
  tags  = var.tags
}

resource "aws_ssm_parameter" "pool_lambda_max_size" {
  name  = "/${var.ssm_prefix}/db/pool/lambda-max-size"
  type  = "String"
  value = tostring(var.pool_lambda_max_size)
  tags  = var.tags
}

locals {
  conexoes_api    = var.app_replicas_max * (var.pool_api_max_size + var.pool_api_migration_max_size)
  conexoes_lambda = var.lambda_concurrency_estimate * var.pool_lambda_max_size
  conexoes_folga  = 10
  conexoes_totais = local.conexoes_api + local.conexoes_lambda + local.conexoes_folga
}

resource "terraform_data" "orcamento_de_conexoes" {
  lifecycle {
    precondition {
      condition     = local.conexoes_totais <= var.db_max_connections
      error_message = "Orcamento de conexoes estourado: ${local.conexoes_totais} necessarias contra ${var.db_max_connections} disponiveis. Reduza os pools ou aumente a classe da instancia."
    }
  }
}
