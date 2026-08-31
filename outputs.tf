output "api_endpoint" {
  description = "A URL base do API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}
