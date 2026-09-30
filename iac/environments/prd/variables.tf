variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket do backend remoto, de onde vem o state de rede. Vazio deriva de servicetrack-tfstate-<conta>."
  type        = string
  default     = ""
}
