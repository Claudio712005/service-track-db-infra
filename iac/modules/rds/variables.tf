variable "name" {
  description = "Prefixo dos recursos, no formato <projeto>-<ambiente>."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "ssm_prefix" {
  description = "Prefixo dos parametros no SSM. O repositorio de infraestrutura le a partir dele."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde o banco vive. Lida do state de rede do repositorio de infraestrutura."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas do subnet group. O banco nunca e publicamente acessivel."
  type        = list(string)
}

variable "db_name" {
  type = string
}

variable "db_username" {
  description = "Usuario master. As roles de aplicacao e de migracao sao criadas depois, pelo bootstrap."
  type        = string
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage" {
  type = number
}

variable "db_max_allocated_storage" {
  description = "Teto do autoscaling de storage. Igual ao alocado desliga o autoscaling."
  type        = number
}

variable "db_engine_version" {
  type = string
}

variable "db_parameter_group_family" {
  type = string
}

variable "db_multi_az" {
  description = "Standby sincrono em outra AZ. Praticamente dobra o custo da instancia."
  type        = bool
}

variable "db_backup_retention_days" {
  description = "Dias de retencao de backup automatico. Zero desliga."
  type        = number
}

variable "db_max_connections" {
  description = <<-EOT
    Teto de conexoes do PostgreSQL. Precisa acomodar a soma dos pools de todos os
    consumidores mais folga administrativa:

      API   = replicas do HPA x (pool default + pool de migracao)
      Lambda = concorrencia x pool por container
      folga  = superusuario, manutencao e o job de bootstrap

    Sem esse calculo o HPA derruba o banco justamente sob a carga que ele existe
    para atender.
  EOT
  type        = number
}

variable "db_idle_in_transaction_timeout_ms" {
  description = "Encerra transacoes ociosas que seguram conexao. Zero desliga."
  type        = number
}

variable "db_log_min_duration_ms" {
  description = "Registra consultas acima deste tempo. -1 desliga."
  type        = number
}

variable "pool_api_max_size" {
  description = "Conexoes maximas do datasource principal da aplicacao, por pod."
  type        = number
}

variable "pool_api_migration_max_size" {
  description = "Conexoes maximas do datasource de migracao da aplicacao, por pod. O Flyway usa poucas e so na subida."
  type        = number
}

variable "pool_lambda_max_size" {
  description = <<-EOT
    Conexoes maximas por container da Lambda. A Lambda atende uma requisicao por
    container de cada vez, entao qualquer valor acima de 2 e desperdicio e
    aumenta a chance de esgotar o banco sob concorrencia.
  EOT
  type        = number
}

variable "app_replicas_max" {
  description = "Teto de replicas do HPA da aplicacao. Usado apenas para conferir o orcamento de conexoes."
  type        = number
}

variable "lambda_concurrency_estimate" {
  description = "Concorrencia estimada da Lambda. Usada apenas para conferir o orcamento de conexoes."
  type        = number
}
