resource "aws_instance" "benchmark_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  ebs_optimized = true
  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  user_data            = <<-EOF
              #!/bin/bash
              # Execute benchmarking script
              aws s3 cp s3://${aws_s3_bucket.startup_script_bucket.bucket}/${aws_s3_object.startup_script.key} /tmp/startup_script.sh
              chmod +x /tmp/startup_script.sh
              /tmp/startup_script.sh "${aws_s3_bucket.startup_script_bucket.bucket}" "${aws_s3_bucket.same_region_bucket.bucket}" "${aws_s3_bucket.other_region_bucket.bucket}" default_aws_config
              # Update AWS CLI configuration to be better optimized for this high performance instance
              mkdir -p ~/.aws
              cat <<EOT >> ~/.aws/config
              [default]
              s3 =
                  max_concurrent_requests = 64
                  multipart_threshold = 1GB
                  multipart_chunksize = 256MB
              EOT
              # Execute benchmarking script
              /tmp/startup_script.sh "${aws_s3_bucket.startup_script_bucket.bucket}" "${aws_s3_bucket.same_region_bucket.bucket}" "${aws_s3_bucket.other_region_bucket.bucket}" optimized_aws_config
              EOF
  iam_instance_profile = aws_iam_instance_profile.benchmark_instance_profile.name
}

resource "aws_ebs_volume" "benchmark_volume" {
  count = 12

  availability_zone = aws_instance.benchmark_instance.availability_zone
  size              = 1126
  type              = "gp3"
  iops              = 16000
  throughput        = 1000
}

resource "aws_volume_attachment" "benchmark_volume_attachment" {
  for_each    = { for idx, vol in aws_ebs_volume.benchmark_volume : idx => vol }
  device_name = "/dev/sd${["f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q"][each.key]}"
  volume_id   = each.value.id
  instance_id = aws_instance.benchmark_instance.id
}
