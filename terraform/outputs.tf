output "server_address" {
  value       = "${google_compute_address.minecraft.address}:${var.server_port}"
  description = "Paste this into Minecraft's Add Server screen."
}

output "server_ip" {
  value       = google_compute_address.minecraft.address
  description = "Static public IP of the server."
}

output "bucket_name" {
  value       = google_storage_bucket.data.name
  description = "GCS bucket holding world backups + the cached server pack."
}

output "bucket_owner_project" {
  value       = var.bucket_project != "" ? var.bucket_project : var.project_id
  description = "Which project owns the data bucket (the data's permanent home)."
}

output "ssh_command" {
  value       = "gcloud compute ssh minecraft-arsenal --zone ${var.zone} --project ${var.project_id}"
  description = "SSH in via IAP (no open SSH port needed)."
}

output "tail_bootstrap_log" {
  value       = "gcloud compute ssh minecraft-arsenal --zone ${var.zone} --project ${var.project_id} --command 'sudo tail -f /var/log/minecraft-bootstrap.log'"
  description = "Watch first-boot install progress."
}
