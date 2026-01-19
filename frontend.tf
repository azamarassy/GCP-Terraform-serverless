provider "google" {
  project = var.project_id
  region  = var.region
}

# 静的webサイトホスティング用のGCSバケット作成
resource "google_storage_bucket" "frontend" {
  name          = var.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

# GCSバケットへのパブリックアクセスを許可
resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.frontend.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}








# --- GCP CDN and Load Balancer ---

# CDN用のグローバルIPアドレスを予約
resource "google_compute_global_address" "cdn_ip" {
  name = "cdn-ip"
}

# GCSバケットをバックエンドとして設定
resource "google_compute_backend_bucket" "frontend_backend" {
  name        = "frontend-backend-bucket"
  bucket_name = google_storage_bucket.frontend.name
  enable_cdn  = true
}

# URLマップを作成
resource "google_compute_url_map" "url_map" {
  name            = "url-map"
  default_service = google_compute_backend_bucket.frontend_backend.id
}

# HTTPプロキシを作成
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "http-proxy"
  url_map = google_compute_url_map.url_map.id
}

# 転送ルールを作成
resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name       = "http-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
  ip_address = google_compute_global_address.cdn_ip.address
}
