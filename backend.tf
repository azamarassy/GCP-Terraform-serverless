# Terraformのバックエンド設定
terraform {
  # Terraformの状態ファイル（.tfstate）をGCSバケットに保存するように設定
  backend "gcs" {
    bucket  = "terraform-state-bucket-gcp" # 状態ファイルを保存するGCSバケットの名前
    prefix  = "terraform/state"            # バケット内の状態ファイルのパス（プレフィックス）
  }
}