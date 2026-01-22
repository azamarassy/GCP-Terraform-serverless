# `terraform apply` の実行後、API Gatewayのデフォルトホスト名（URL）を出力
output "api_gateway_url" {
  description = "The URL of the API Gateway." # 出力値の説明
  value       = "https://${google_api_gateway_gateway.gateway.default_hostname}" # API GatewayのURL
}

# Cloud FunctionのトリガーURLを出力
output "cloud_function_url" {
  description = "The URL of the Cloud Function." # 出力値の説明
  value       = google_cloudfunctions2_function.backend_function.service_config[0].uri # Cloud FunctionのURL
}

# フロントエンドのCDN/ロードバランサに割り当てられたグローバルIPアドレスを出力
output "cdn_ip_address" {
  description = "The IP address of the CDN." # 出力値の説明
  value       = google_compute_global_address.cdn_ip.address # IPアドレス
}

# 作成されたCloud DNSマネージドゾーンのネームサーバーリストを出力
output "dns_name_servers" {
  description = "The name servers for the Cloud DNS zone." # 出力値の説明
  value       = google_dns_managed_zone.zone.name_servers # ネームサーバーのリスト
}
