resource "random_string" "bucket_suffix" {
  length  = 16
  special = false
  upper   = false
}

resource "aws_s3_bucket" "startup_script_bucket" {
  bucket        = "benchmark-same-region-bucket-${random_string.bucket_suffix.result}"
  force_destroy = true
}

resource "aws_s3_object" "startup_script" {
  bucket = aws_s3_bucket.startup_script_bucket.id
  key    = "startup_benchmarking_script.sh"
  source = "../benchmarking/startup_benchmarking_script.sh"
}

resource "aws_s3_bucket" "same_region_bucket" {
  bucket        = "benchmark-same-region-bucket-2-${random_string.bucket_suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "other_region_bucket" {
  provider      = aws.other_region
  bucket        = "benchmark-other-region-bucket-${random_string.bucket_suffix.result}"
  force_destroy = true
}
