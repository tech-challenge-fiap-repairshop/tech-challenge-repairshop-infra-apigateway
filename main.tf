# Busca dados da conta AWS e região atual
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  api_name         = "repairshop-apigw-${var.environment}"
  lambda_auth_name = "repairshop-lambda-auth-${var.environment}"

  # ARN determinístico da Lambda de Autenticação (não quebra o destroy se a Lambda já tiver sido excluída)
  lambda_invoke_arn = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.lambda_auth_name}/invocations"

  # Se a busca dinâmica via data "aws_lb" encontrar o Load Balancer no EKS, utiliza o DNS dele na porta 8080.
  # Caso contrário, utiliza o valor informado na variável var.app_lb_url como fallback.
  app_lb_dns_name = try(data.aws_lb.app_k8s[0].dns_name, "") != "" ? "http://${data.aws_lb.app_k8s[0].dns_name}:8080" : (var.app_lb_url != "" ? var.app_lb_url : "http://localhost:8080")
}

# -----------------------------------------------------------------------------
# Busca Dinâmica Segura na AWS: Localiza o Load Balancer criado pelo Kubernetes (EKS)
# Utiliza aws_lbs (plural) para não lançar erro fatal caso o EKS/LB já tenha sido destruído
# -----------------------------------------------------------------------------
data "aws_lbs" "app_k8s" {
  tags = {
    "kubernetes.io/service-name" = "${var.k8s_namespace}/${var.k8s_service_name}"
  }
}

data "aws_lb" "app_k8s" {
  count = var.use_dynamic_lb_lookup && length(data.aws_lbs.app_k8s.arns) > 0 ? 1 : 0
  arn   = tolist(data.aws_lbs.app_k8s.arns)[0]
}

# API Gateway V2 (HTTP API)
resource "aws_apigatewayv2_api" "api" {
  name          = local.api_name
  protocol_type = "HTTP"
  description   = "API Gateway para o projeto RepairShop (${var.environment})"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]
    max_age       = 300
  }
}

# Default Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

# -----------------------------------------------------------------------------
# ROTA 1: Auth Lambda (POST /auth/login)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "auth_lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = local.lambda_invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth_login" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /auth/login"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda.id}"
}

# -----------------------------------------------------------------------------
# ROTA 2: Proxy Catch-all (EKS Application Load Balancer / App Spring Boot)
# Mapeia dinamicamente os endpoints da aplicação buscando o DNS do Load Balancer
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "app_proxy" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = "${local.app_lb_dns_name}/{proxy}"
  integration_method = "ANY"
}

resource "aws_apigatewayv2_route" "app_proxy_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app_proxy.id}"
}

resource "aws_apigatewayv2_integration" "app_root" {
  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = local.app_lb_dns_name
  integration_method = "ANY"
}

resource "aws_apigatewayv2_route" "app_root_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.app_root.id}"
}
