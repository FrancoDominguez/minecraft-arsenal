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

**What does *not* travel with the account: the IP.** The static external IP
(`google_compute_address`) is permanent within whichever compute account is
active, but a reserved IP is a project-scoped resource — GCP won't let a VM in
project B use an IP reserved in project A. So unlike the bucket, the IP can't be
parked in the permanent account. If you want a connect address that survives an
account move, put a **DNS A record** (a zone you control) in front of the IP and
repoint it after the move. The bucket holds the world; DNS holds the address.

## Updating the modpack (alpha — expect frequent bumps)

ATM11 is alpha. To move to a new pack build, edit `.env`:

1. `curseforge_server_file_id` → the new *ServerFiles* zip file ID.
2. `neoforge_version` (and `minecraft_version` / `java_version` if they changed).
3. `terraform apply`, then recreate/reboot the VM.

**Dropping to ATM10 (stable):** same three vars, pointed at ATM10's project/file
IDs and its versions (MC 1.21.1, NeoForge 21.1.x, Java 21). Nothing else changes.

## Finding the CurseForge IDs

Easiest: run the helper (reads the API key from `.env`):

```bash
python3 scripts/find-atm-server-file.py            # ATM11
python3 scripts/find-atm-server-file.py all-the-mods-10   # stable fallback
```

It prints `curseforge_project_id` and lists every **ServerFiles** zip with its
file ID + game version + date — pick one for `curseforge_server_file_id`.

> Note (2026-06-27): for ATM11 the helper finds the project (id `1148445`) but
> reports "No ServerFiles found" — ATM11 doesn't publish standalone ServerFiles
> entries. Instead each **client** file carries a `serverPackFileId` pointing at
> the matching server pack. The helper now lists those; use the newest
> `serverPackFileId` (e.g. `8304510` for client 0.1.2) as
> `curseforge_server_file_id`. `bootstrap.sh`'s `GET /v1/mods/{id}/files/{fileId}`
> resolves that file ID fine. (Follow-up: have the helper emit a copy-paste-ready
> `TF_VAR_curseforge_server_file_id=` line.)

The API key that was 403'ing on 2026-06-26 now works (verified 2026-06-27).

Manually, if you prefer: the API key is free at <https://console.curseforge.com/>
→ API Keys; the project ID comes from `GET /v1/mods/search` and the ServerFiles
file ID from `GET /v1/mods/{id}/files` (the file with `isServerPack: true`).

> Note (2026-06-26): the helper is verified to issue the correct request, but the
> key supplied so far returns `403 API Key missing or invalid` — regenerate/verify
> the key before relying on auto-download.

## Cost (us/Montréal, on-demand)

| Item | ~Monthly |
|---|---|
| e2-standard-4 VM compute, 24/7 (vCPU + RAM) | ~$98 |
| 60 GB pd-ssd (the VM's boot disk; billed separately from compute) | ~$10 |
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
