# Cloud Functions用のサービスアカウントを作成
resource "google_service_account" "function_sa" {
  account_id   = "gcf-sa"                         # サービスアカウントのID
  display_name = "Cloud Function Service Account" # サービスアカウントの表示名
}

# Cloud Functionsのソースコードをアップロードするための一時的なGCSバケットを作成
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-gcf-source" # バケット名
  location      = var.region                      # ロケーション
  force_destroy = true                            # バケット削除時にオブジェクトがあっても強制的に削除
}

# Cloud Functionsのソースコード（`functions`ディレクトリ）をZIP形式にアーカイブ
data "archive_file" "function_zip" {
  type        = "zip"                             # アーカイブの種類
  source_dir  = "${path.module}/functions"        # ソースディレクトリ
  output_path = "${path.module}/tmp/function.zip" # 出力先のパス
}

# アーカイブしたソースコードをGCSバケットにアップロード
resource "google_storage_bucket_object" "function_source_object" {
  name   = "source.zip"                                       # GCS上のオブジェクト名
  bucket = google_storage_bucket.function_source.name         # アップロード先のバケット
  source = data.archive_file.function_zip.output_path         # アップロードするファイルのパス
}

# Cloud Function（第2世代）リソースを定義
resource "google_cloudfunctions2_function" "backend_function" {
  name     = "backend-function" # Cloud Functionの名前
  location = var.region         # デプロイするリージョン

  # ビルドに関する設定
  build_config {
    runtime     = "python39"      # ランタイム環境
    entry_point = "handler"       # 実行する関数名 (main.py内の関数)
    source {
      # ソースコードの場所を指定
      storage_source {
        bucket = google_storage_bucket.function_source.name       # ソースコードが格納されているGCSバケット
        object = google_storage_bucket_object.function_source_object.name # ソースコードのオブジェクト名 (ZIPファイル)
      }
    }
  }

  # サービスに関する設定
  service_config {
    max_instance_count = 1                                  # 最大インスタンス数
    min_instance_count = 0                                  # 最小インスタンス数
    available_memory   = "256Mi"                            # 利用可能なメモリ
    timeout_seconds    = 60                                 # タイムアウト時間（秒）
    service_account_email = google_service_account.function_sa.email # 実行に使用するサービスアカウント
    all_traffic_on_latest_revision = true                  # すべてのトラフィックを最新のリビジョンに送信
  }
}

# Cloud Functionを公開APIとして誰でも呼び出せるようにIAMポリシーを設定
resource "google_cloud_run_service_iam_member" "invoker" {
  location = google_cloudfunctions2_function.backend_function.location # Cloud Functionのロケーション
  service  = google_cloudfunctions2_function.backend_function.name     # 対象のCloud Runサービス（=Cloud Function）
  role     = "roles/run.invoker"                                     # Cloud Run起動元のロールを付与
  member   = "allUsers"                                              # すべてのユーザーに許可
}

# --- API Gateway ---

# API GatewayのAPIリソースを定義
resource "google_api_gateway_api" "api" {
  provider = google-beta    # google-betaプロバイダーを使用
  api_id   = "my-backend-api" # APIのID
}

# API GatewayのAPI設定（OpenAPI仕様）を定義
resource "google_api_gateway_api_config" "api_config" {
  provider      = google-beta                 # google-betaプロバイダーを使用
  api           = google_api_gateway_api.api.api_id # 対象のAPI
  api_config_id = "my-backend-api-config"     # API設定のID

  # OpenAPI仕様のドキュメントを設定
  openapi_documents {
    document {
      path     = "spec.yaml" # ドキュメントのパス名
      # テンプレートファイルからOpenAPI仕様を生成
      contents = templatefile("${path.module}/spec.yaml.tftpl", {
        function_url = google_cloudfunctions2_function.backend_function.service_config[0].uri # Cloud FunctionのトリガーURLを埋め込む
      })
    }
  }

  # ライフサイクル設定: 変更時に新しいリソースを先に作成してから古いリソースを削除
  lifecycle {
    create_before_destroy = true
  }
}

# API Gatewayのゲートウェイリソースを定義
resource "google_api_gateway_gateway" "gateway" {
  provider      = google-beta                          # google-betaプロバイダーを使用
  api_config    = google_api_gateway_api_config.api_config.id # 使用するAPI設定
  gateway_id    = "my-backend-gateway"               # ゲートウェイのID
  region        = var.region                         # デプロイするリージョン
}
