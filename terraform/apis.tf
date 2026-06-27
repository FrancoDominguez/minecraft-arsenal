# Enable every GCP API this stack needs, so `terraform apply` works against a
# brand-new project with nothing turned on — that's the "spin it up under a
# fresh account" goal (see docs/ARCHITECTURE.md, account portability).
#
# disable_on_destroy = false: a `terraform destroy` should NOT yank the API out
# from under anything else in the project (and re-enabling is slow/flaky).

# Compute Engine — the VM, static IP, firewall rules. On the compute project.
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Secret Manager — the CurseForge key + RCON password. On the compute project.
resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Cloud Storage — the world-data bucket. Enabled on the BUCKET-owning project
# via the aliased storage provider, which may differ from the compute project.
resource "google_project_service" "storage" {
  provider           = google.storage
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}
