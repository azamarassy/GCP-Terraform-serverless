# API GatewayのAPIキーを出力します。
output "api_key_value" {
  description = "The API Gateway API Key value to use for authentication."
  value       = aws_api_gateway_api_key.api_key.value
  sensitive   = true # 機密情報として扱い、コンソールに直接表示されないようにします。
}

# API Gatewayの実行URLを出力します。
output "api_gateway_url" {
  description = "The URL of the API Gateway Stage."
  value       = aws_api_gateway_stage.prod.invoke_url
}

# Lambda関数のARNを出力します。
output "lambda_function_arn" {
  description = "The ARN of the Lambda function."
  value       = aws_lambda_function.backend_lambda.arn
}

# Lambda関数のCloudWatch Logs group nameを出力します。
output "lambda_log_group" {
  description = "The CloudWatch Logs group name for the Lambda function."
  value       = "/aws/lambda/${aws_lambda_function.backend_lambda.function_name}"
}
