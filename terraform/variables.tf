# ---------------------------------------------------------------------------
# Compute account (the VM, IP, firewall, secrets)
# ---------------------------------------------------------------------------
variable "project_id" {
  type        = string
  description = "GCP project ID that runs the Minecraft VM (the account paying for compute)."
}

variable "credentials_file" {
  type        = string
  default     = ""
  description = "Path to a service-account JSON key for the compute project. Leave empty to use ADC / gcloud auth."
}

variable "region" {
  type        = string
  default     = "northamerica-northeast1" # Montréal — closest to the players
  description = "GCP region for the VM."
}

variable "zone" {
  type        = string
  default     = "northamerica-northeast1-a"
  description = "GCP zone for the VM."
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-4" # 4 vCPU / 16 GB, ~$98/mo on-demand. Bump to e2-standard-8 if ATM10 lags.
  description = "Compute Engine machine type."
}

variable "boot_disk_size_gb" {
  type        = number
  default     = 60
  description = "Boot/data disk size. ATM10 + a world needs room; 60GB is comfortable. GCS is the durable copy."
}

variable "boot_disk_type" {
  type        = string
  default     = "pd-ssd"
  description = "Disk type. pd-ssd keeps chunk I/O snappy for a big modpack."
}

# ---------------------------------------------------------------------------
# Storage account (the GCS bucket — world data + backups). Optional override.
# ---------------------------------------------------------------------------
variable "bucket_name" {
  type        = string
  description = "Globally-unique name for the world/backup bucket, e.g. minecraft-arsenal-data."
}

variable "bucket_project" {
  type        = string
  default     = ""
  description = "GCP project that OWNS the data bucket. Empty = same as project_id (self-contained). Set to a permanent account for cross-account portability."
}

variable "bucket_region" {
  type        = string
  default     = ""
  description = "Region for the bucket. Empty = same as region."
}

variable "bucket_credentials_file" {
  type        = string
  default     = ""
  description = "SA JSON key for the bucket-owning account. Empty = reuse credentials_file."
}

variable "bucket_storage_class" {
  type        = string
  default     = "STANDARD" # Cheapest sensible class for daily-written / boot-read data. Avoid COLDLINE/ARCHIVE (retrieval + min-duration fees).
  description = "GCS storage class for the data bucket."
}

variable "backup_retention_days" {
  type        = number
  default     = 14
  description = "Daily backups older than this are auto-deleted by a lifecycle rule."
}

# ---------------------------------------------------------------------------
# Minecraft / All the Mods 10 — all parameterized so bumping the pack version
# (or switching packs entirely) = change these few values.
# ---------------------------------------------------------------------------
variable "minecraft_version" {
  type        = string
  default     = "1.21.1"
  description = "Minecraft version ATM10 targets."
}

variable "neoforge_version" {
  type        = string
  default     = "21.1.180"
  description = "NeoForge build for the pack (the line ATM10 7.x ServerFiles ship). Informational — the pack's bundled NeoForge installer is authoritative. Bump alongside the pack version."
}

variable "java_version" {
  type        = string
  default     = "21"
  description = "Temurin JDK major version. Must match what the pack's NeoForge build is compiled for — ATM10 / MC 1.21.1 / NeoForge 21.1.x needs Java 21."
}

variable "curseforge_project_id" {
  type        = string
  default     = "925200" # All the Mods 10 (ATM10). See docs/ARCHITECTURE.md.
  description = "CurseForge numeric project ID for All the Mods 10."
}

variable "curseforge_server_file_id" {
  type        = string
  default     = "8323948" # ServerFiles-7.1.zip (newest ATM10 as of 2026-06-28)
  description = "CurseForge file ID of the ATM10 *ServerFiles* zip to pin. Bump to update the pack."
}

variable "curseforge_api_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "CurseForge API key, used to auto-download the server pack. Stored in Secret Manager, never in git."
}

variable "jvm_heap" {
  type        = string
  default     = "12G" # ~12G heap on a 16G box, leaving ~4G for OS/off-heap. ATM10 wants 10-12G.
  description = "Max JVM heap (-Xmx). Keep a few GB headroom under total RAM."
}

# ---------------------------------------------------------------------------
# Networking / access
# ---------------------------------------------------------------------------
variable "server_port" {
  type        = number
  default     = 25565
  description = "Minecraft Java listen port (TCP)."
}

variable "rcon_password" {
  type        = string
  sensitive   = true
  description = "RCON password. Used by the backup script to flush saves cleanly. Stored in Secret Manager."
}

variable "allowed_player_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"] # Minecraft is public by design; whitelist controls who can actually join.
  description = "CIDRs allowed to reach the Minecraft port."
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  default     = [] # Empty = no public SSH firewall rule; use IAP or gcloud compute ssh. Add your IP/32 to open it.
  description = "CIDRs allowed to SSH (port 22). Keep tight."
}
