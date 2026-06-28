# Architecture

A single always-on GCP VM runs **All the Mods 11** (NeoForge, MC 26.1.2, Java 25).
World data is backed up daily to a GCS bucket and restored automatically onto any
fresh VM — so the *data* outlives any individual VM (or even GCP account).

```
                    ┌─────────────────────── GitHub: minecraft-arsenal ──────────────────────┐
                    │  terraform/  (infra)      server/  (scripts + config, versioned)        │
                    └───────────────┬────────────────────────────────────────────────────────┘
                                    │ terraform apply
                                    ▼
        ┌─────────────────── Compute account (project_id) ───────────────────┐
        │  e2-standard-4 VM ──run.sh──> ATM11 NeoForge server (Java 25)       │
        │     ▲  startup.sh: sync deploy/ from bucket, run bootstrap.sh       │
        │     │  systemd: minecraft.service + minecraft-backup.timer (daily)  │
        └─────┼──────────────────────────────────────────────────────────────┘
              │ restore on fresh boot          │ daily backup (RCON-clean)
              ▼                                 ▼
        ┌──────────── Storage account (bucket_project, optional) ─────────────┐
        │  gs://<bucket>/  deploy/         scripts + config (uploaded by TF)   │
        │                  serverpack/     cached ATM11 ServerFiles zip        │
        │                  client/         cached client pack + manifest.json  │
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
- **APIs are enabled by Terraform.** `apis.tf` turns on Compute, Secret Manager
  (compute project) and Storage (bucket project) via `google_project_service`, so
  `terraform apply` works on a brand-new project with nothing pre-enabled — no
  manual `gcloud services enable` step. `disable_on_destroy = false` so a destroy
  doesn't yank an API out from under the project.
- **Mods aren't in git.** ATM11 is a ~CurseForge pack; the official *ServerFiles*
  zip is pinned by file ID and fetched via the CurseForge API, then cached in the
  bucket as an upstream-outage fallback. Git pins *which* version; the bucket
  holds the *bytes*. (packwiz-per-mod was rejected — some CF mods disable
  third-party download, which breaks per-mod fetches.)
- **The client pack is published the same way.** The matching *client* pack (the
  sibling file of the ServerFiles for the same pack version — it carries the
  client-only/UI mods the ServerFiles strip) is the source of truth for "what a
  friend must install to join". Bootstrap caches its zip under `client/` and
  writes `client/manifest.json` (`client_file_id`, `client_pack_object`,
  `server_address`, versions). The future one-click installer reads that manifest
  → pulls the cached zip → pre-points the client at the server, with **no
  CurseForge key on the friend's machine**. Pinned by `curseforge_client_file_id`;
  best-effort (never blocks server boot); skipped when that var is empty. How the
  manifest/zip get *exposed* to friends (public object vs signed URL) is decided
  in the installer PR — for now they live in the (private) bucket.

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
2. `curseforge_client_file_id` → the matching *client* file ID for that same
   version (so the one-click installer stays in lockstep with the server).
3. `neoforge_version` (and `minecraft_version` / `java_version` if they changed).
4. `terraform apply`, then recreate/reboot the VM.

**Dropping to ATM10 (stable):** same three vars, pointed at ATM10's project/file
IDs and its versions (MC 1.21.1, NeoForge 21.1.x, Java 21). Nothing else changes.

## Finding the CurseForge IDs

Easiest: run the helper (reads the API key from `.env`):

```bash
python3 scripts/find-atm-server-file.py            # ATM11
python3 scripts/find-atm-server-file.py all-the-mods-10   # stable fallback
```

It prints `curseforge_project_id` and lists the pack files newest-first. For
ATM11 it shows each **client file** paired with its **server pack** file ID, so
you fill both vars from one line: `client_file_id` → `curseforge_client_file_id`,
`server_file_id` → `curseforge_server_file_id`. (For packs that publish
standalone ServerFiles, like ATM10, it lists those directly instead.)

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
