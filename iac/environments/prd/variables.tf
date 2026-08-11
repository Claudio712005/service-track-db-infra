variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket do backend remoto. Usado para ler o state de rede do repositorio de infraestrutura."
  type        = string
  default     = "servicetrack-tfstate-821146464895"
}
