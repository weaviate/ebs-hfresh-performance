output "server_instance_id" {
  value = aws_instance.server.id
}

output "client_instance_id" {
  value = aws_instance.client.id
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "data_volume_id" {
  value = var.data_disk == "ebs" ? aws_ebs_volume.data[0].id : "none"
}

output "results_bucket" {
  value = aws_s3_bucket.results.bucket
}

output "region" {
  value = var.region
}

output "eice_id" {
  value = aws_ec2_instance_connect_endpoint.eice.id
}
