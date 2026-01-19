# API GatewayのURLを出力します。
output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = "https://${google_api_gateway_gateway.gateway.default_hostname}"
}

# Cloud FunctionのURLを出力します。
output "cloud_function_url" {
  description = "The URL of the Cloud Function."
  value       = google_cloudfunctions2_function.backend_function.service_config[0].uri
}

# CDNのIPアドレスを出力します。
output "cdn_ip_address" {
  description = "The IP address of the CDN."
  value       = google_compute_global_address.cdn_ip.address
}

# Cloud DNSのネームサーバーを出力します。
output "dns_name_servers" {
  description = "The name servers for the Cloud DNS zone."
  value       = google_dns_managed_zone.zone.name_servers
}
