# minecraft-arsenal

Terraform + bootstrap for an always-on **All the Mods 11** Minecraft server on
GCP, with daily world backups to GCS and automatic restore onto any fresh VM.

- **Pack:** All the Mods 11 (NeoForge, MC 26.1.2, Java 21) — version-pinned, easy to bump or drop to ATM10
- **Host:** `e2-standard-4` (4 vCPU / 16 GB, ~12 GB heap), always-on, Montréal (`northamerica-northeast1`), ~$110/mo
- **Durability:** daily RCON-clean backups to GCS; fresh VMs restore the latest world automatically
- **Portable:** the data bucket can live in a permanent account separate from whoever runs the VM

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design.

## Quick start

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Fill in: project_id, bucket_name, CurseForge IDs + API key, rcon_password
terraform init
terraform apply
```

Then watch the first-boot install (downloads the pack, ~a few minutes):

```bash
gcloud compute ssh minecraft-arsenal --zone northamerica-northeast1-a \
  --command 'sudo tail -f /var/log/minecraft-bootstrap.log'
```

`terraform output server_address` gives the IP:port to put in Minecraft. Add
yourself to the allow-list once the server is up (server console or RCON):
`/whitelist add <yourname>`.

## What you need first

1. A GCP project with billing enabled.
2. A free **CurseForge API key** (<https://console.curseforge.com/> → API Keys).
3. The ATM11 **project ID** and **ServerFiles file ID** (see `docs/ARCHITECTURE.md`).

## Layout

```
terraform/   infra: VM, IP, firewall, GCS bucket, Secret Manager, script upload
server/      bootstrap + backup + restore scripts, systemd units, server config
docs/        architecture & operations
```

## Common operations

| Task | How |
|---|---|
| Update the pack | bump `curseforge_server_file_id` (+ versions) in tfvars → `terraform apply` → reboot VM |
| Manual backup now | `sudo systemctl start minecraft-backup.service` |
| Restore is automatic | a fresh VM with no local world pulls `backups/world-latest.tar.zst` |
| Run under buddy's creds | set `bucket_project` to your permanent account, hand him the repo, he `apply`s |
| Scale up if laggy | set `machine_type = "e2-standard-8"` → `terraform apply` |

> Note: All the Mods 11 is in **alpha** — expect frequent pack updates and the
> occasional breaking change. Everything version-related is a Terraform variable,
> so bumping (or falling back to ATM10) is a small tfvars edit.
