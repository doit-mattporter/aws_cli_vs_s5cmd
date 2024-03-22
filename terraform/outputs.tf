output "instance_id" {
  value = aws_instance.benchmark_instance.id
}

output "volume_ids" {
  value = aws_ebs_volume.benchmark_volume.*.id
}
