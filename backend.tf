terraform {
    required_providers {
      aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
      }
    }
}

provider "aws" {
  region = "ap-northeast-1"
}


# CloudFrontのオリジンとなるREST APIを作成
resource "aws_api_gateway_rest_api" "api" {
    name       = "my-backend-api"
    description = "Backend REST API for the application"

    endpoint_configuration {
      types = ["REGIONAL"] # APIのエンドポイントをリージョナルタイプにすることを指定
  }
}


# 新しいパスの作成(各パスに独自の機能を持たせるために作成)
resource "aws_api_gateway_resource" "data" {
    rest_api_id = aws_api_gateway_rest_api.api.id # どのAPI Gatewayリソースか指定
    parent_id   = aws_api_gateway_rest_api.api.root_resource_id # どのパスの下に新しいパスを作成するかを指定
    path_part   = "data" # 新たに作成するパス名を定義
}

# AWS API Gateway で特定の API エンドポイントに対する HTTP メソッド を定義
resource "aws_api_gateway_method" "data_get" {
    rest_api_id = aws_api_gateway_rest_api.api.id # どのREST APIか指定
    resource_id = aws_api_gateway_resource.data.id # パスを指定
    http_method = "GET" # HTTPメソッドを指定
    authorization = "NONE" # このメソッドへのアクセスは認証不要
    api_key_required = true # このメソッドへのアクセスはAPIキーが必要
}

resource "aws_api_gateway_integration" "data_get_integration" {
    rest_api_id = aws_api_gateway_rest_api.api.id # どのAPI Gatewayリソースか指定
    resource_id = aws_api_gateway_resource.data.id # パスを指定
    http_method = aws_api_gateway_method.data_get.http_method # 
    type        = "AWS_PROXY" # Lambda統合でLambdaファンクションを呼び出し
    integration_http_method = "POST" # Lambdaファンクションを呼び出す際のHTTPメソッド（常にPOST）
    uri         = aws_lambda_function.backend_lambda.invoke_arn # Lambdaファンクションのinvoke ARN
}

# API Gateway method response
resource "aws_api_gateway_method_response" "data_get_200" {
    rest_api_id = aws_api_gateway_rest_api.api.id
    resource_id = aws_api_gateway_resource.data.id
    http_method = aws_api_gateway_method.data_get.http_method
    status_code = "200"
}

# API Gateway integration response
resource "aws_api_gateway_integration_response" "data_get_200" {
    rest_api_id = aws_api_gateway_rest_api.api.id
    resource_id = aws_api_gateway_resource.data.id
    http_method = aws_api_gateway_method.data_get.http_method
    status_code = aws_api_gateway_method_response.data_get_200.status_code
    depends_on = [aws_api_gateway_integration.data_get_integration]
}

# API GatewayのAPIをデプロイ, REST APIは明示的にデプロイの設定をしないと自動デプロイできない
resource "aws_api_gateway_deployment" "api_deployment" {
    rest_api_id = aws_api_gateway_rest_api.api.id # デプロイ対象となるREST APIを指定

    triggers = { # デプロイメントリソースを再実行するためのトリガー
        redeployment = sha1(jsonencode([ # デプロイメントの変更を監視したいリソースのIDやボディをJSON形式の文字列に変換
        # terraform apply実行時に↑のJSON文字列のハッシュ値を再計算し、変更有の場合このaws_api_gateway_deploymentリソースが再実行されAPI Gatewayで新しいデプロイが作成される
            aws_api_gateway_rest_api.api.body,
            aws_api_gateway_resource.data.id,
            aws_api_gateway_method.data_get.id,
            aws_api_gateway_integration.data_get_integration.id,
            aws_api_gateway_method_response.data_get_200.id,
            aws_api_gateway_integration_response.data_get_200.id,
            aws_lambda_function.backend_lambda.source_code_hash,
            aws_lambda_permission.api_gateway_invoke.statement_id,
            "apikey-required-20250909-3" # APIキー必須設定のための強制更新
        ]))
    }

    lifecycle {
      create_before_destroy = true # 既存のAPI Gatewayを削除してから新しいリソースを作成することでダウンタイムを最小限に抑える
    }
}

# API Gatewayのステージ
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

# APIキーの作成
resource "aws_api_gateway_api_key" "api_key" {
  name = "backend-api-key"
}

# APIキーとステージの関連付け
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "prod-usage-plan"
  description = "Usage plan for production stage"

  # 全体のスロットリングを定義（適度な値に設定）
  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }

  api_stages { # この利用プランを適用するAPIとステージを指定
    api_id = aws_api_gateway_rest_api.api.id # どのAPIにこのプランを適用するか指定
    stage  = aws_api_gateway_stage.prod.stage_name # どのステージにこのプランを適用するか指定
    
    # レート制限の設定, DDos攻撃対策
    throttle {
      path        = "/data/GET"
      rate_limit  = 100
      burst_limit = 200
    }
  }
}

# 作成したAPIキーと利用プランを関連付け
# 特定の API キーを持つユーザーが、その利用プランで定義されたスロットリングやクォータの制限を受ける
resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id # APIキーを指定
  key_type      = "API_KEY" # キーのタイプを指定
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id # 利用プランを指定
}


# Lambda関数用のIAMロール
resource "aws_iam_role" "lambda_role" {
  name = "backend-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda関数の基本実行ロールポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda関数のソースコードをZIP化
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/backend.py"
  output_path = "${path.module}/lambda/backend.zip"
}

# Lambda関数
resource "aws_lambda_function" "backend_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "backend-lambda"
  role            = aws_iam_role.lambda_role.arn
  handler         = "backend.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }
}

# API GatewayがLambdaを呼び出すための権限
resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway-v2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

# 追加の権限設定: 特定のメソッドに対する権限
resource "aws_lambda_permission" "api_gateway_invoke_data" {
  statement_id  = "AllowExecutionFromAPIGatewayData-v2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/GET/data"
}