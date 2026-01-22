# GCPプロジェクトIDを定義する変数
variable "project_id" {
  description = "The GCP project ID to deploy resources to." # 変数の説明: リソースをデプロイするGCPプロジェクトのID
  type        = string                                     # 変数の型: 文字列
}

# GCPリージョンを定義する変数
variable "region" {
  description = "The GCP region to deploy resources to." # 変数の説明: リソースをデプロイするGCPリージョン
  type        = string                                   # 変数の型: 文字列
  default     = "asia-northeast1"                        # デフォルト値: 東京リージョン
}

# アプリケーションのメインドメイン名を定義する変数
variable "domain_name" {
  description = "The main domain name for the application." # 変数の説明: アプリケーションのメインドメイン名
  type        = string                                      # 変数の型: 文字列
  default     = "example.com"                               # デフォルト値: example.com
}

# GCSバケット名を定義する変数
variable "bucket_name" {
  description = "The name for the GCS bucket." # 変数の説明: GCSバケットの名前
  type        = string                         # 変数の型: 文字列
  default     = "sample-gcs-bucket-name"       # デフォルト値: "sample-gcs-bucket-name"
}