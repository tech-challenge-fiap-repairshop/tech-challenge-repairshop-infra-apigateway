variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente (dev, hml, prd)"
  type        = string
}

variable "s3_tfstate_bucket" {
  description = "Nome do Bucket S3 para controle de estado do Terraform"
  type        = string
  default     = ""
}

variable "app_lb_url" {
  description = "URL fallback do Load Balancer (caso a busca dinâmica esteja desativada ou falhe)"
  type        = string
  default     = "http://localhost:8080"
}

variable "use_dynamic_lb_lookup" {
  description = "Se true, busca os Load Balancers na AWS via tag do Kubernetes service"
  type        = bool
  default     = true
}

variable "k8s_namespace" {
  description = "Namespace do Kubernetes onde os services das aplicações foram criados"
  type        = string
  default     = "repairshop"
}

variable "k8s_service_port" {
  description = "Porta padrão exposta pelos Load Balancers dos microsserviços no EKS"
  type        = number
  default     = 8080
}
