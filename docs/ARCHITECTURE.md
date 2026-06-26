# Architecture

A single always-on GCP VM runs **All the Mods 11** (NeoForge, MC 26.1.2, Java 21).
World data is backed up daily to a GCS bucket and restored automatically onto any
fresh VM — so the *data* outlives any individual VM (or even GCP account).

```
                    ┌─────────────────────── GitHub: minecraft-arsenal ──────────────────────┐
                    │  terraform/  (infra)      server/  (scripts + config, versioned)        │
                    └───────────────┬────────────────────────────────────────────────────────┘
                                    │ terraform apply
                                    ▼
        ┌─────────────────── Compute account (project_id) ───────────────────┐
        │  e2-standard-4 VM ──run.sh──> ATM11 NeoForge server (Java 21)       │
        │     ▲  startup.sh: sync deploy/ from bucket, run bootstrap.sh       │
        │     │  systemd: minecraft.service + minecraft-backup.timer (daily)  │
        └─────┼──────────────────────────────────────────────────────────────┘
              │ restore on fresh boot          │ daily backup (RCON-clean)
              ▼                                 ▼
        ┌──────────── Storage account (bucket_project, optional) ─────────────┐
        │  gs://<bucket>/  deploy/         scripts + config (uploaded by TF)   │
        │                  serverpack/     cached ATM11 ServerFiles zip        │
        │                  backups/        world-<ts>.tar.zst + world-latest   │
        └─────────────────────────────────────────────────────────────────────┘
```

## Why this shape

- **The VM is disposable; the bucket is the source of truth.** `terraform destroy`
  + re-`apply` rebuilds the VM and restores the latest world. No separate
  persistent disk to babysit.
- **Scripts live in git, run from the bucket.** Terraform uploads `server/` to
  `deploy/`; the tiny startup script syncs it and runs `bootstrap.sh`. Editing a
  script = `terraform apply` (re-upload) + reboot (re-sync).
- **Mods aren't in git.** ATM11 is a ~CurseForge pack; the official *ServerFiles*
  zip is pinned by file ID and fetched via the CurseForge API, then cached in the
  bucket as an upstream-outage fallback. Git pins *which* version; the bucket
  holds the *bytes*. (packwiz-per-mod was rejected — some CF mods disable
  third-party download, which breaks per-mod fetches.)

## Account portability (the "run from my buddy's creds later" goal)

Two GCP providers (see `terraform/providers.tf`):

- **compute provider** — VM, IP, firewall, secrets. Whoever pays for compute.
- **storage provider** (aliased) — the data bucket. Defaults to the compute
  account, but set `bucket_project` / `bucket_credentials_file` to a **permanent
  account you control** and the world data lives there forever. The VM's service
  account is granted `storage.objectAdmin` on the bucket regardless of owner.

So: buddy runs `terraform apply` with his creds → VM in his project, but it
reads/writes the same canonical bucket and restores the same world.

## Updating the modpack (alpha — expect frequent bumps)

ATM11 is alpha. To move to a new pack build, edit `terraform.tfvars`:

1. `curseforge_server_file_id` → the new *ServerFiles* zip file ID.
2. `neoforge_version` (and `minecraft_version` / `java_version` if they changed).
3. `terraform apply`, then recreate/reboot the VM.

**Dropping to ATM10 (stable):** same three vars, pointed at ATM10's project/file
IDs and its versions (MC 1.21.1, NeoForge 21.1.x, Java 21). Nothing else changes.

## Finding the CurseForge IDs

- Get a free API key at <https://console.curseforge.com/> → API Keys.
- `curseforge_project_id`: the numeric mod ID for ATM11 (from the CurseForge API
  `GET /v1/mods/search`, or the project page).
- `curseforge_server_file_id`: on the ATM11 Files page, open the **ServerFiles**
  zip for the version you want; the file ID is in its URL / the API
  `GET /v1/mods/{id}/files`.

## Cost (us/Montréal, on-demand)

| Item | ~Monthly |
|---|---|
| e2-standard-4 VM (24/7) | ~$98 |
| 60 GB pd-ssd | ~$10 |
| GCS storage (few GB) + egress | <$1 |
| **Total** | **~$110** |

A 1-year committed-use discount drops the VM to ~$60/mo. Bump
`machine_type` to `e2-standard-8` if ATM11 lags with several players.

## Security notes

- Secrets (CurseForge API key, RCON password) live in **Secret Manager**, fetched
  at boot. Never in git, never in plain instance metadata.
- No public SSH by default — use `gcloud compute ssh` (IAP) or set
  `allowed_ssh_cidrs` to your IP/32.
- `white-list=true` by default: the game port is public, but only allow-listed
  players can join. Add players with `/whitelist add <name>` via RCON or console.
