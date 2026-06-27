# The compute provider — owns the VM, firewall, IP, service account, secrets.
# This is "whoever is paying for the server this month" (you, or your buddy).
provider "google" {
  project     = var.project_id
  region      = var.region
  zone        = var.zone
  credentials = var.credentials_file != "" ? file(var.credentials_file) : null
}

# The storage provider — owns the GCS bucket that holds world data + backups.
#
# This is the key to account portability: by default it inherits the compute
# project/creds (everything lands in one account, fully self-contained). But set
# bucket_project / bucket_credentials_file to point it at a PERMANENT account you
# control, and the world data lives there forever while the compute VM can be
# spun up under anyone's creds. The VM's service account is granted access to the
# bucket regardless of which account owns it (see main.tf).
provider "google" {
  alias   = "storage"
  project = var.bucket_project != "" ? var.bucket_project : var.project_id
  region  = var.bucket_region != "" ? var.bucket_region : var.region
  credentials = var.bucket_credentials_file != "" ? file(var.bucket_credentials_file) : (
    var.credentials_file != "" ? file(var.credentials_file) : null
  )
}
