# Dedicated service account for the VM (least privilege: bucket + the 2 secrets).
resource "google_service_account" "minecraft" {
  account_id   = "minecraft-arsenal-vm"
  display_name = "Minecraft Arsenal VM"
}

# Stable public IP so the connect address never changes across reboots.
resource "google_compute_address" "minecraft" {
  name   = "minecraft-arsenal-ip"
  region = var.region
}

# Open the Minecraft port to players.
resource "google_compute_firewall" "minecraft" {
  name    = "minecraft-arsenal-allow-game"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.server_port)]
  }

  source_ranges = var.allowed_player_cidrs
  target_tags   = ["minecraft-arsenal"]
}

# Optional SSH rule — only created if you list CIDRs. Otherwise use
# `gcloud compute ssh` (IAP) which needs no open port.
resource "google_compute_firewall" "ssh" {
  count   = length(var.allowed_ssh_cidrs) > 0 ? 1 : 0
  name    = "minecraft-arsenal-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = ["minecraft-arsenal"]
}

resource "google_compute_instance" "minecraft" {
  name         = "minecraft-arsenal"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["minecraft-arsenal"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.minecraft.address
    }
  }

  service_account {
    email  = google_service_account.minecraft.email
    scopes = ["cloud-platform"] # IAM does the real gating; this just enables the APIs.
  }

  # Minimal startup script: render runtime config, sync deploy/ from the bucket,
  # run bootstrap.sh. All heavy logic lives in the git-versioned server/ scripts.
  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tpl", {
    bucket_name           = google_storage_bucket.data.name
    minecraft_version     = var.minecraft_version
    neoforge_version      = var.neoforge_version
    java_version          = var.java_version
    jvm_heap              = var.jvm_heap
    server_port           = var.server_port
    curseforge_project_id = var.curseforge_project_id
    curseforge_file_id    = var.curseforge_server_file_id
    cf_secret_id          = google_secret_manager_secret.curseforge_api_key.secret_id
    rcon_secret_id        = google_secret_manager_secret.rcon_password.secret_id
    backup_retention_days = var.backup_retention_days
  })

  # Make sure the bucket, scripts, secrets, and IAM exist before first boot.
  depends_on = [
    google_storage_bucket_iam_member.vm_access,
    google_storage_bucket_object.deploy,
    google_secret_manager_secret_iam_member.cf_key_access,
    google_secret_manager_secret_iam_member.rcon_access,
  ]
}
