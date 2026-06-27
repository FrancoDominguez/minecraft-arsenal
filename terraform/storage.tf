# The data bucket: world backups + a cached copy of the server pack.
# Created via the aliased "storage" provider so it can live in a different
# account than the compute VM (see providers.tf).
resource "google_storage_bucket" "data" {
  provider = google.storage

  name          = var.bucket_name
  location      = var.bucket_region != "" ? var.bucket_region : var.region
  storage_class = var.bucket_storage_class

  # Uniform access — IAM only, no per-object ACLs.
  uniform_bucket_level_access = true

  # Keep a version history so a corrupted world can be rolled back. Cost impact is
  # small: noncurrent versions are billed as ordinary storage at the same class
  # rate, and the num_newer_versions=5 lifecycle rule below caps history at 5 old
  # copies per object. Daily backups are already distinct timestamped objects, so
  # versioning only multiplies storage for objects that get overwritten in place.
  # Worst case ~5x the size of a few overwritten GB ≈ a few GB extra ≈ <$0.20/mo.
  versioning {
    enabled = true
  }

  # Prune old daily backups. Only objects under backups/ expire; the cached
  # server pack under serverpack/ and the deploy scripts are kept.
  lifecycle_rule {
    condition {
      age            = var.backup_retention_days
      matches_prefix = ["backups/"]
    }
    action {
      type = "Delete"
    }
  }

  # Clean up noncurrent (versioned) objects so history doesn't grow forever.
  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
}

# Grant the VM's service account read/write on the bucket. This works even when
# the bucket is owned by a different account — that's what makes the VM portable.
resource "google_storage_bucket_iam_member" "vm_access" {
  provider = google.storage

  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.minecraft.email}"
}
