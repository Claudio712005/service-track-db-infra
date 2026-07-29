output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = var.db_name
}

output "username" {
  value = var.db_username
}

output "password" {
  value     = random_password.db.result
  sensitive = true
}

output "jdbc_url" {
  value = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}"
}

output "security_group_id" {
  description = "SG do banco. O repositorio de infraestrutura cria as regras de ingress apontando para ele."
  value       = aws_security_group.rds.id
}

output "multi_az" {
  value = aws_db_instance.this.multi_az
}

output "max_connections" {
  value = var.db_max_connections
}

output "ssm_prefix" {
  value = var.ssm_prefix
}

output "orcamento_de_conexoes" {
  description = "Distribuicao do teto de conexoes entre os consumidores."
  value = {
    teto        = var.db_max_connections
    aplicacao   = local.conexoes_api
    lambda      = local.conexoes_lambda
    folga       = local.conexoes_folga
    total_usado = local.conexoes_totais
  }
}

output "roles_de_runtime" {
  description = "Usuarios das roles. As senhas ficam apenas no SSM."
  value       = var.roles_de_runtime
}
