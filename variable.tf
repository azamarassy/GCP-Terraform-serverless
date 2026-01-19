variable "domain_name" {
  description = "The main domain name for the application."
  type        = string
  default     = "example.com"
}

variable "region" {
  type = string
  default = "ap-northeast-1"
}

variable "bucket_name" {
  type = string
  default = "sample-bucket-name"
}