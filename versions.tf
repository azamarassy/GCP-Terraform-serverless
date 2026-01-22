# Terraform自体の設定
terraform {
  # この構成が要求するTerraformの最小バージョンを指定
  required_version = ">= 1.0"

  # 必要なTerraformプロバイダーとそのバージョンを指定
  required_providers {
    # Google Cloud Platform (GCP) の公式プロバイダー
    google = {
      source  = "hashicorp/google" # プロバイダーのソース（取得元）
      version = "~> 5.0"           # 要求するプロバイダーのバージョン（5.0以上、6.0未満）
    }
    # GCPのベータ版機能を含むプロバイダー
    google-beta = {
      source  = "hashicorp/google-beta" # プロバイダーのソース
      version = "~> 5.0"                # 要求するプロバイダーのバージョン
    }
  }
}
