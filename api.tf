# Cloud Functions用のサービスアカウント
resource "google_service_account" "function_sa" {
  account_id   = "gcf-sa"
  display_name = "Cloud Function Service Account"
}

# Cloud Functionsでコードをアップロードするための一時的なGCSバケット
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-gcf-source"
  location      = var.region
  force_destroy = true
}

# Cloud FunctionsのソースコードをZIP化
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions"
  output_path = "${path.module}/tmp/function.zip"
}

# GCSにソースコードをアップロード
resource "google_storage_bucket_object" "function_source_object" {
  name   = "source.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_zip.output_path
}

# Cloud Function (第2世代)
resource "google_cloudfunctions2_function" "backend_function" {
  name     = "backend-function"
  location = var.region

  build_config {
    runtime     = "python39"
    entry_point = "handler" # main.py内の関数名
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_object.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "256Mi"
    timeout_seconds    = 60
    service_account_email = google_service_account.function_sa.email
    all_traffic_on_latest_revision = true
  }
}

# Cloud Functionを公開APIとしてアクセス可能にする
resource "google_cloud_run_service_iam_member" "invoker" {
  location = google_cloudfunctions2_function.backend_function.location
  service  = google_cloudfunctions2_function.backend_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
