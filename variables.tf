variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente (dev, hml, prd)"
  type        = string
}

variable "app_lb_url" {
  description = "URL fallback do Load Balancer (caso a busca dinâmica esteja desativada ou falhe)"
  type        = string
  default     = ""
}

variable "use_dynamic_lb_lookup" {
  description = "Se true, busca o Load Balancer na AWS via tag do Kubernetes service"
  type        = bool
  default     = true
}

variable "k8s_namespace" {
  description = "Namespace do Kubernetes onde o service da aplicação foi criado"
  type        = string
  default     = "repairshop"
}

variable "k8s_service_name" {
  description = "Nome do Service do Kubernetes (type: LoadBalancer) da aplicação"
  type        = string
  default     = "repairshop-service"
}
