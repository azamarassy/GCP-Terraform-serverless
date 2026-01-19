# 既存のHosted Zoneを参照
data "aws_route53_zone" "primary" {
    name         = var.domain_name
    private_zone = false
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# ACM証明書発行
resource "aws_acm_certificate" "cert" {
    provider          = aws.us-east-1
    domain_name       = var.domain_name # ドメイン名を指定
    validation_method = "DNS" # DNS検証を指定
    subject_alternative_names = ["*.${var.domain_name}"] # サブドメインも含めて検証
    lifecycle {
        create_before_destroy = true # 既存の証明書を消す前に新規作成することでダウンタイムをなくす
    }
}

# ACMを発行する際、ドメインがユーザーのものか確認するためにDNSレコードを作成してawsが確認するためのコード
resource "aws_route53_record" "cert_validation" {
    for_each = { # DNSレコード検証に必要な情報（レコードセット : レコード名、タイプ、値など） を格納
        for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
            name   = dvo.resource_record_name
            type   = dvo.resource_record_type
            record = dvo.resource_record_value
        }
    }
    allow_overwrite = true
    zone_id = data.aws_route53_zone.primary.zone_id # DNSレコードを作成するホストゾーンを指定
    name    = each.value.name # for_eachで取得したnameの値を取得
    type    = each.value.type # CNAMEなどのレコードタイプを取得
    ttl     = 60              # レコードのキャッシュ有効期限を60秒に設定
    records = [each.value.record] # DNSレコードの値を取得
}

# ACM証明書の発行プロセスにおいて、DNS検証が完了するのを待機
resource "aws_acm_certificate_validation" "cert" {
    provider                = aws.us-east-1
    certificate_arn         = aws_acm_certificate.cert.arn # 証明書を指定
    validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn] # サブドメインの作成も含めて待機
}

# 静的webサイトホスティング用のS3作成
resource "aws_s3_bucket" "frontend" {
    bucket = var.bucket_name
    force_destroy = true
}

# バケットのパブリックアクセスをブロック
resource "aws_s3_bucket_public_access_block" "frontend" {
    bucket = aws_s3_bucket.frontend.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

# CloudFrontからのアクセスのみ許可するバケットポリシーを設定
resource "aws_s3_bucket_policy" "frontend" {
    bucket = aws_s3_bucket.frontend.id # バケットを指定
    policy = data.aws_iam_policy_document.s3_policy.json # ポリシーを設定
}

data "aws_caller_identity" "current" {}

# OACからのアクセスを許可するためのポリシーを定義
data "aws_iam_policy_document" "s3_policy" {
    statement {
       principals {
            type        = "Service"
            identifiers = ["cloudfront.amazonaws.com"]
        }

    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    
    condition {
    test     = "StringEquals"
    variable = "AWS:SourceAccount"
    values   = [data.aws_caller_identity.current.account_id]
    }
  }
}



# API Gateway 用（AllViewer ポリシー）
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# API Gateway用のカスタムorigin request policy（カスタムヘッダー転送用）
resource "aws_cloudfront_origin_request_policy" "api_gateway_policy" {
  provider = aws.us-east-1
  name     = "api-gateway-policy"
  comment  = "Policy for API Gateway origin with custom headers"
  
  cookies_config {
    cookie_behavior = "none"
  }
  
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Content-Type"]
    }
  }
  
  query_strings_config {
    query_string_behavior = "all"
  }
}


# CloudFront経由でのみS3にアクセスできるようにするOAC (Origin Access Control)
resource "aws_cloudfront_origin_access_control" "frontend_oac" {
    name                              = "frontend-oac" # OAC設定につける名前
    description                       = "OAC for frontend distribution"
    signing_behavior                  = "always" # 署名付きリクエスト(サーバー間の認証メカニズム)CloudFrontがS3バケットにアクセスする際に、常にリクエストに署名するよう指定
    signing_protocol                  = "sigv4" # リクエストに署名するために使用するプロトコルを指定
    origin_access_control_origin_type = "s3" # OAC設定が適用されるオリジンの種類を指定
}

resource "aws_cloudfront_distribution" "s3_distribution" {
    provider = aws.us-east-1
    enabled = true                                        # CloudFrontディストリビューションを有効化
    aliases = [var.domain_name, "www.${var.domain_name}"] # wwwありなし両方でCloudFrontディストリビューションにアクセス可能
    default_root_object = "index.html"                   # ルートパスアクセス時のデフォルトファイル

    origin {
        domain_name                = aws_s3_bucket.frontend.bucket_regional_domain_name # CloudFrontがコンテンツを取得するS3バケットのドメイン名を指定
        origin_id                  = aws_s3_bucket.frontend.id # オリジンを一意に識別するためのIDを指定
        origin_access_control_id   = aws_cloudfront_origin_access_control.frontend_oac.id # *オリジンアクセス制御（OAC）**のIDを指定
    }

    default_cache_behavior {
        allowed_methods = ["GET", "HEAD"] # CloudFrontがオリジンにリクエストを送信する際に許可されるHTTPメソッドを指定
        cached_methods  = ["GET", "HEAD"]            # CloudFrontがキャッシュできるHTTPメソッドを指定
        target_origin_id = aws_s3_bucket.frontend.id # デフォルトのキャッシュ動作が適用されるオリジンのIDを指定
        viewer_protocol_policy = "redirect-to-https" # HTTPリクエストをHTTPSにリダイレクトするよう指定
        compress = true 
                                     # CloudFrontがコンテンツを圧縮して配信するよう指定
        cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized ポリシーのID。静的コンテンツ（例：画像、CSS、JavaScriptファイルなど）のキャッシュに最適化された設定

    }
    
    restrictions {
    geo_restriction {
        restriction_type = "whitelist" # リストにある国からのアクセスを許可する
        locations        = ["JP"]      # 許可する国を日本（JP）に設定
      }
    }

    viewer_certificate {
        acm_certificate_arn = aws_acm_certificate_validation.cert.certificate_arn # CloudFrontがHTTPS接続を確立するために使用するACM証明書のARNを指定
        ssl_support_method  = "sni-only" # SSL/TLSのサポート方法を指定
        minimum_protocol_version = "TLSv1.2_2021" # 最低限のTLSバージョンを指定
    }

    web_acl_id = aws_wafv2_web_acl.frontend_waf.arn # CloudFrontディストリビューションに**WAF (Web Application Firewall)**を関連付ける設定

    # API Gatewayへのオリジン設定
    origin {
    origin_id = "api-gateway-origin"
    domain_name = "${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com"
    origin_path = "/prod"  # ステージパスを指定
    # カスタムヘッダーでAPIキーを渡す設定

    custom_header {
      name  = "X-API-Key"
      value = aws_api_gateway_api_key.api_key.value
    }

    custom_origin_config {
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "https-only"
    origin_ssl_protocols   = ["TLSv1.2"]
    origin_read_timeout    = 60
    origin_keepalive_timeout = 5
      }
    }

# S3でホスティングされた静的ファイル（例：/index.html）へのリクエストはS3に、動的データ取得（例：/data、/data/info）へのリクエストはAPI Gatewayにルーティング
    # /data（末尾スラッシュなし）へのリクエスト用
    ordered_cache_behavior {
    path_pattern     = "/data" # CloudFrontのパス（origin_pathの/prodと組み合わせて/prod/dataになる）
    target_origin_id = "api-gateway-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress = true
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingDisabled ポリシーのID。CloudFrontでのキャッシュを無効にするための設定
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api_gateway_policy.id # カスタムポリシー（カスタムヘッダー転送）
    }

    # /data/*（サブパス）へのリクエスト用
    ordered_cache_behavior {
    path_pattern     = "/data/*" # CloudFrontのパス（origin_pathの/prodと組み合わせて/prod/data/*になる）
    target_origin_id = "api-gateway-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress = true
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingDisabled ポリシーのID。CloudFrontでのキャッシュを無効にするための設定
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api_gateway_policy.id # カスタムポリシー（カスタムヘッダー転送）
    }
}

# WAFの設定
resource "aws_wafv2_web_acl" "frontend_waf" {
    provider = aws.us-east-1
    name = "frontend-waf" # WAFの名前
    scope = "CLOUDFRONT" # WAFの適用範囲
    description = "WAF for frontend distribution"

    default_action { # Web ACLに含まれるどのルールにも一致しなかったリクエストに対して、WAFが取るべきアクションを定義
        allow {} # デフォルトのアクションを「許可」に設定。つまり、明示的に拒否するルールがない限り、すべてのトラフィックが通過
    }

# クロスサイトスクリプティングをブロックするルールを追加
    rule {
        name     = "AWSManagedRulesCommonRuleSetRule"
        priority = 1
        
        statement {
            managed_rule_group_statement {
                name        = "AWSManagedRulesCommonRuleSet"
                vendor_name = "AWS"
            }
        }
        
        visibility_config {
            cloudwatch_metrics_enabled = true
            metric_name                = "AWSManagedRulesCommonRuleSetRuleMetric"
            sampled_requests_enabled   = true
        }
        
        override_action {
            none {}
        }
    }

    visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "FrontendWebAcl"
        sampled_requests_enabled   = true
    }
}

# CloudFrontディストリビューションにドメイン名を紐づけ
resource "aws_route53_record" "www" {
    zone_id = data.aws_route53_zone.primary.zone_id
    name    = "www.${var.domain_name}"
    type    = "A"

    alias { # cloudforntは固定のipを持たないのでAliasレコードを使用して設定
        name                   = aws_cloudfront_distribution.s3_distribution.domain_name
        zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
        evaluate_target_health = false
    }
}

resource "aws_route53_record" "root" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
