resource "aws_instance" "benchmark_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  ebs_optimized = true

  user_data            = <<-EOF
              #!/bin/bash
              aws s3 cp s3://${aws_s3_bucket.startup_script_bucket.bucket}/${aws_s3_object.startup_script.key} /tmp/startup_script.sh
              chmod +x /tmp/startup_script.sh
              /tmp/startup_script.sh "${aws_s3_bucket.startup_script_bucket.bucket}" "${aws_s3_bucket.same_region_bucket.bucket}" "${aws_s3_bucket.other_region_bucket.bucket}"
              EOF
  iam_instance_profile = aws_iam_instance_profile.benchmark_instance_profile.name
}

resource "aws_ebs_volume" "benchmark_volume" {
  count = 4

  availability_zone = aws_instance.benchmark_instance.availability_zone
  size              = 1024
  type              = "gp3"
  iops              = 16000
  throughput        = 1000
}

resource "aws_volume_attachment" "benchmark_volume_attachment" {
  for_each    = { for idx, vol in aws_ebs_volume.benchmark_volume : idx => vol }
  device_name = "/dev/sd${["f", "g", "h", "i"][each.key]}"
  volume_id   = each.value.id
  instance_id = aws_instance.benchmark_instance.id
}
