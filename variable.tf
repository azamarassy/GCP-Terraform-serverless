variable "project_id" {
  description = "The GCP project ID to deploy resources to."
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources to."
  type        = string
  default     = "asia-northeast1"
}

variable "domain_name" {
  description = "The main domain name for the application."
  type        = string
  default     = "example.com"
}

variable "bucket_name" {
  description = "The name for the GCS bucket."
  type        = string
  default     = "sample-gcs-bucket-name"
}