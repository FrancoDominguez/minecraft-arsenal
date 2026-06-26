# Ship the server scripts + config into the bucket under deploy/. The VM's
# startup script just syncs this folder and runs bootstrap.sh — so the
# git-versioned scripts become the single source of truth, and updating them is
# `terraform apply` (re-upload) + reboot (re-sync).

locals {
  deploy_files = {
    "bootstrap.sh"                     = "${path.module}/../server/bootstrap.sh"
    "backup.sh"                        = "${path.module}/../server/backup.sh"
    "restore.sh"                       = "${path.module}/../server/restore.sh"
    "systemd/minecraft.service"        = "${path.module}/../server/systemd/minecraft.service"
    "systemd/minecraft-backup.service" = "${path.module}/../server/systemd/minecraft-backup.service"
    "systemd/minecraft-backup.timer"   = "${path.module}/../server/systemd/minecraft-backup.timer"
    "config/server.properties"         = "${path.module}/../server/config/server.properties"
    "config/user_jvm_args.txt"         = "${path.module}/../server/config/user_jvm_args.txt"
  }
}

resource "google_storage_bucket_object" "deploy" {
  provider = google.storage
  for_each = local.deploy_files

  bucket = google_storage_bucket.data.name
  name   = "deploy/${each.key}"
  source = each.value
  # The provider hashes `source` and re-uploads automatically when it changes,
  # so editing a script + `terraform apply` re-deploys it; a reboot re-syncs it.
}
