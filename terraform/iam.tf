resource "aws_iam_instance_profile" "benchmark_instance_profile" {
  name = var.instance_profile_name
  role = aws_iam_role.benchmark_role.name
}

resource "aws_iam_role" "benchmark_role" {
  name = var.instance_profile_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "benchmark_policy" {
  name = var.policy_name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:*"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.startup_script_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.startup_script_bucket.bucket}/*",
          "arn:aws:s3:::${aws_s3_bucket.same_region_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.same_region_bucket.bucket}/*",
          "arn:aws:s3:::${aws_s3_bucket.other_region_bucket.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.other_region_bucket.bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "benchmark_policy_attachment" {
  role       = aws_iam_role.benchmark_role.name
  policy_arn = aws_iam_policy.benchmark_policy.arn
}
