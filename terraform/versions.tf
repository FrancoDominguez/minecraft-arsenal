terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Optional remote state. Uncomment and point at a GCS bucket you already own
  # if you want shared/portable state. Local state works fine for a solo setup.
  # backend "gcs" {
  #   bucket = "my-tfstate-bucket"
  #   prefix = "minecraft-arsenal"
  # }
}
