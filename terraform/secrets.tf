# Secrets live in Secret Manager, fetched by the VM at boot — never in git,
# never in plain instance metadata. The secretmanager.googleapis.com API is
# enabled in apis.tf (google_project_service.secretmanager).

resource "google_secret_manager_secret" "curseforge_api_key" {
  secret_id = "minecraft-arsenal-curseforge-api-key"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "curseforge_api_key" {
  secret      = google_secret_manager_secret.curseforge_api_key.id
  secret_data = var.curseforge_api_key
}

resource "google_secret_manager_secret" "rcon_password" {
  secret_id = "minecraft-arsenal-rcon-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "rcon_password" {
  secret      = google_secret_manager_secret.rcon_password.id
  secret_data = var.rcon_password
}

# Let the VM read just these two secrets.
resource "google_secret_manager_secret_iam_member" "cf_key_access" {
  secret_id = google_secret_manager_secret.curseforge_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.minecraft.email}"
}

resource "google_secret_manager_secret_iam_member" "rcon_access" {
  secret_id = google_secret_manager_secret.rcon_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.minecraft.email}"
}
