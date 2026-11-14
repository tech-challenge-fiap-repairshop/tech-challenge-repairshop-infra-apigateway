# Busca dados da conta AWS e região atual
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  api_name         = "repairshop-apigw-${var.environment}"
  lambda_auth_name = "repairshop-lambda-auth-${var.environment}"

  # ARN determinístico da Lambda de Autenticação (não quebra o destroy se a Lambda já tiver sido excluída)
  lambda_invoke_arn = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.lambda_auth_name}/invocations"

  # Mapa dos 4 microsserviços no EKS (Fase 4)
  k8s_services = {
    register      = "register-service"
    service_order = "service-order-execution-service"
    payment       = "payment-service"
    notification  = "notification-service"
  }

  fallback_base_url = var.app_lb_url != "" ? var.app_lb_url : "http://localhost:${var.k8s_service_port}"

  service_urls = {
    for key, _ in local.k8s_services :
    key => try(data.aws_lb.services[key].dns_name, "") != "" ? "http://${data.aws_lb.services[key].dns_name}:${var.k8s_service_port}" : local.fallback_base_url
  }

  proxy_routes = {
    auth_register = {
      route_key          = "POST /auth/register"
      integration_method = "POST"
      target_url         = "${local.service_urls["register"]}/auth/register"
    }
    customers_root = {
      route_key          = "ANY /customers"
      integration_method = "ANY"
      target_url         = "${local.service_urls["register"]}/customers"
    }
    customers_proxy = {
      route_key          = "ANY /customers/{proxy+}"
      integration_method = "ANY"
      target_url         = "${local.service_urls["register"]}/customers/{proxy}"
    }
    vehicles_root = {
      route_key          = "ANY /vehicles"
      integration_method = "ANY"
      target_url         = "${local.service_urls["register"]}/vehicles"
    }
    vehicles_proxy = {
      route_key          = "ANY /vehicles/{proxy+}"
      integration_method = "ANY"
      target_url         = "${local.service_urls["register"]}/vehicles/{proxy}"
    }
    service_orders_root = {
      route_key          = "ANY /service-orders"
      integration_method = "ANY"
      target_url         = "${local.service_urls["service_order"]}/service-orders"
    }
    service_orders_proxy = {
      route_key          = "ANY /service-orders/{proxy+}"
      integration_method = "ANY"
      target_url         = "${local.service_urls["service_order"]}/service-orders/{proxy}"
    }
    execute_task_proxy = {
      route_key          = "POST /execute_task/{proxy+}"
      integration_method = "POST"
      target_url         = "${local.service_urls["service_order"]}/execute_task/{proxy}"
    }
    increment_execution_task_proxy = {
      route_key          = "POST /increment_execution_task/{proxy+}"
      integration_method = "POST"
      target_url         = "${local.service_urls["service_order"]}/increment_execution_task/{proxy}"
    }
    payment_proxy = {
      route_key          = "ANY /payment/{proxy+}"
      integration_method = "ANY"
      target_url         = "${local.service_urls["payment"]}/payment/{proxy}"
    }
    payments_root = {
      route_key          = "ANY /payments"
      integration_method = "ANY"
      target_url         = "${local.service_urls["payment"]}/payments"
    }
    payments_proxy = {
      route_key          = "ANY /payments/{proxy+}"
      integration_method = "ANY"
      target_url         = "${local.service_urls["payment"]}/payments/{proxy}"
    }
    notifications_root = {
      route_key          = "ANY /notifications"
      integration_method = "ANY"
      target_url         = "${local.service_urls["notification"]}/notifications"
    }
    notifications_proxy = {
      route_key          = "ANY /notifications/{proxy+}"
      integration_method = "ANY"
      target_url         = "${local.service_urls["notification"]}/notifications/{proxy}"
    }
  }
}

# -----------------------------------------------------------------------------
# Busca Dinâmica Segura na AWS: Localiza os 4 Load Balancers criados pelo EKS
# Utiliza aws_lbs (plural) para não lançar erro fatal caso o EKS/LB já tenha sido destruído
# -----------------------------------------------------------------------------
data "aws_lbs" "services" {
  for_each = local.k8s_services

  tags = {
    "kubernetes.io/service-name" = "${var.k8s_namespace}/${each.value}"
  }
}

data "aws_lb" "services" {
  for_each = {
    for key, lbs in data.aws_lbs.services :
    key => tolist(lbs.arns)[0]
    if var.use_dynamic_lb_lookup && length(lbs.arns) > 0
  }

  arn = each.value
}

# API Gateway V2 (HTTP API)
resource "aws_apigatewayv2_api" "api" {
  name          = local.api_name
  protocol_type = "HTTP"
  description   = "API Gateway para o projeto RepairShop (${var.environment})"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token", "traceparent", "tracestate"]
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
# ROTAS 2..N: Proxy por Bounded Context para os 4 Microsserviços no EKS (Porta 8080)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "services" {
  for_each = local.proxy_routes

  api_id             = aws_apigatewayv2_api.api.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = each.value.target_url
  integration_method = each.value.integration_method
}

resource "aws_apigatewayv2_route" "services" {
  for_each = local.proxy_routes

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.services[each.key].id}"
}

