# Googleプロバイダーの設定
provider "google" {
  project = var.project_id # プロジェクトIDをvariable.tfから参照
  region  = var.region     # リージョンをvariable.tfから参照
}

# 静的Webサイトホスティング用のGCSバケットを作成
resource "google_storage_bucket" "frontend" {
  name          = var.bucket_name                     # バケット名をvariable.tfから参照
  location      = var.region                          # バケットのロケーション（リージョン）をvariable.tfから参照
  force_destroy = true                                # バケット内にオブジェクトが残っていても削除を強制する

  uniform_bucket_level_access = true # 均一なバケットレベルのアクセス制御を有効にする

  website {
    main_page_suffix = "index.html" # メインページとしてindex.htmlを指定
    not_found_page   = "404.html"   # 404エラーページとして404.htmlを指定
  }
}

# GCSバケットへのパブリックアクセスを許可するためのIAMポリシーを設定
resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.frontend.name # 対象のGCSバケット
  role   = "roles/storage.objectViewer"      # ストレージオブジェクト閲覧者のロールを付与
  member = "allUsers"                        # すべてのユーザー（インターネット全体）に適用
}








# --- GCP CDN and Load Balancer ---

# CDN用のグローバル外部IPアドレスを予約
resource "google_compute_global_address" "cdn_ip" {
  name = "cdn-ip" # IPアドレスリソースの名前
}

# GCSバケットをバックエンドとして設定
resource "google_compute_backend_bucket" "frontend_backend" {
  provider = google-beta # google-betaプロバイダーを使用

  name            = "frontend-backend-bucket"         # バックエンドバケットの名前
  bucket_name     = google_storage_bucket.frontend.name # バックエンドとして使用するGCSバケットの名前
  enable_cdn      = true                                # Cloud CDNを有効にする
  security_policy = google_compute_security_policy.armor_policy.name # 適用するCloud Armorセキュリティポリシー
}

# URLマップを作成して、リクエストをバックエンドサービスにルーティング
resource "google_compute_url_map" "url_map" {
  name            = "url-map"                                     # URLマップの名前
  default_service = google_compute_backend_bucket.frontend_backend.id # デフォルトのバックエンドサービスとしてGCSバックエンドバケットを指定
}

# HTTPリクエストを受け取るためのターゲットHTTPプロキシを作成
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "http-proxy"                    # ターゲットHTTPプロキシの名前
  url_map = google_compute_url_map.url_map.id # 使用するURLマップ
}

# グローバル転送ルールを作成して、外部IPアドレスとポートをターゲットHTTPプロキシにマッピング
resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  name       = "http-forwarding-rule"                       # 転送ルールの名前
  target     = google_compute_target_http_proxy.http_proxy.id # 転送先のターゲットHTTPプロキシ
  port_range = "80"                                        # 待ち受けるポート番号 (HTTP)
  ip_address = google_compute_global_address.cdn_ip.address  # 使用するグローバルIPアドレス
}

# --- DNS, SSL and HTTPS Load Balancer ---

# Cloud DNSのマネージドゾーンを作成
resource "google_dns_managed_zone" "zone" {
  name        = "primary-zone"                 # マネージドゾーンの名前
  dns_name    = "${var.domain_name}."          # 管理するDNS名（ドメイン名）
  description = "DNS zone for ${var.domain_name}" # ゾーンの説明
}

# GoogleマネージドSSL証明書を作成
resource "google_compute_managed_ssl_certificate" "ssl_certificate" {
  name    = "managed-cert" # SSL証明書の名前
  managed {
    domains = [var.domain_name, "www.${var.domain_name}"] # 証明書が対象とするドメイン
  }
}

# HTTPSリクエストを受け取るためのターゲットHTTPSプロキシを作成
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "https-proxy"                                           # ターゲットHTTPSプロキシの名前
  url_map          = google_compute_url_map.url_map.id                         # 使用するURLマップ
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_certificate.id] # 使用するSSL証明書
}

# グローバル転送ルールを作成して、外部IPアドレスとポートをターゲットHTTPSプロキシにマッピング
resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {
  name       = "https-forwarding-rule"                        # 転送ルールの名前
  target     = google_compute_target_https_proxy.https_proxy.id # 転送先のターゲットHTTPSプロキシ
  port_range = "443"                                        # 待ち受けるポート番号 (HTTPS)
  ip_address = google_compute_global_address.cdn_ip.address    # 使用するグローバルIPアドレス
}

# ルートドメイン用のDNS Aレコードを作成
resource "google_dns_record_set" "root" {
  name         = google_dns_managed_zone.zone.dns_name         # レコード名（ルートドメイン）
  type         = "A"                                           # レコードタイプ (Aレコード)
  ttl          = 300                                           # TTL（Time To Live）秒
  managed_zone = google_dns_managed_zone.zone.name           # 所属するマネージドゾーン
  rrdatas      = [google_compute_global_address.cdn_ip.address] # Aレコードの値（CDNのIPアドレス）
}

# wwwサブドメイン用のDNS Aレコードを作成
resource "google_dns_record_set" "www" {
  name         = "www.${google_dns_managed_zone.zone.dns_name}" # レコード名 (wwwサブドメイン)
  type         = "A"                                            # レコードタイプ (Aレコード)
  ttl          = 300                                            # TTL（Time To Live）秒
  managed_zone = google_dns_managed_zone.zone.name            # 所属するマネージドゾーン
  rrdatas      = [google_compute_global_address.cdn_ip.address] # Aレコードの値（CDNのIPアドレス）
}

# --- Security (Cloud Armor) ---

# Cloud Armorのセキュリティポリシーを作成
resource "google_compute_security_policy" "armor_policy" {
  name = "armor-policy" # セキュリティポリシーの名前
  description = "Security policy for the load balancer" # ポリシーの説明

  # デフォルトルール：他のどのルールにも一致しないトラフィックを拒否
  rule {
    action   = "deny(403)"    # アクション (403 Forbiddenで拒否)
    priority = 2147483647      # 優先度 (最も低い)
    match {
      versioned_expr = "SRC_IPS_V1" # 一致条件の式
      config {
        src_ip_ranges = ["*"] # すべての送信元IPに一致
      }
    }
    description = "Default deny all" # ルールの説明
  }

  # SQLインジェクション攻撃をブロックするルール
  rule {
    action   = "deny(403)" # アクション (403 Forbiddenで拒否)
    priority = 1000        # 優先度
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')" # 事前設定されたWAFルール 'sqli-stable' を使用
      }
    }
    description = "Block SQL injection" # ルールの説明
  }

  # 日本からのトラフィックのみを許可するルール
  rule {
    action   = "allow" # アクション (許可)
    priority = 100     # 優先度
    match {
      expr {
        expression = "origin.region_code == 'JP'" # 送信元のリージョンコードが 'JP' (日本) の場合に一致
      }
    }
    description = "Allow only from Japan" # ルールの説明
  }
}
