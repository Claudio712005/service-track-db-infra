output "rds_endpoint" {
  value = module.rds.address
}

output "rds_jdbc_url" {
  value = module.rds.jdbc_url
}

output "db_username" {
  value = module.rds.username
}

output "db_password" {
  value     = module.rds.password
  sensitive = true
}

output "rds_security_group_id" {
  description = "Informar ao repositorio de infraestrutura, que cria as regras de ingress."
  value       = module.rds.security_group_id
}

output "multi_az" {
  value = module.rds.multi_az
}

output "orcamento_de_conexoes" {
  value = module.rds.orcamento_de_conexoes
}

output "ssm_prefix" {
  description = "Prefixo onde endpoint, credenciais e orcamento de pool foram publicados."
  value       = module.rds.ssm_prefix
}
