#!/usr/bin/env bash
# First-boot installer for the All the Mods 11 server. Idempotent: safe to
# re-run on every reboot. Run by the GCE startup script after it syncs this
# folder from the bucket. Logs to /var/log/minecraft-bootstrap.log.
set -euo pipefail

source /etc/minecraft/arsenal.env

SRV=/opt/minecraft/server
DEPLOY=/opt/minecraft/deploy
mkdir -p "$SRV"

log() { echo "[bootstrap $(date -u +%H:%M:%S)] $*"; }

# ---------------------------------------------------------------------------
# 1. System packages + Temurin JDK
# ---------------------------------------------------------------------------
if ! command -v "java" >/dev/null || ! java -version 2>&1 | grep -q "\"${JAVA_VERSION}"; then
  log "installing Temurin ${JAVA_VERSION} + tools"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y wget apt-transport-https gpg unzip jq zstd ca-certificates python3
  mkdir -p /etc/apt/keyrings
  wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
  echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release; echo "$VERSION_CODENAME") main" \
    > /etc/apt/sources.list.d/adoptium.list
  apt-get update -y
  apt-get install -y "temurin-${JAVA_VERSION}-jdk"
fi

# ---------------------------------------------------------------------------
# 2. Secrets from Secret Manager
# ---------------------------------------------------------------------------
log "fetching secrets"
CF_API_KEY=$(gcloud secrets versions access latest --secret="$CF_SECRET_ID" 2>/dev/null || true)
RCON_PASSWORD=$(gcloud secrets versions access latest --secret="$RCON_SECRET_ID")
# Persist rcon password for the backup unit (root-only).
umask 077
echo "RCON_PASSWORD=${RCON_PASSWORD}" > /etc/minecraft/rcon.env
umask 022

# ---------------------------------------------------------------------------
# 3. Install the ATM11 server pack (only if not already installed)
# ---------------------------------------------------------------------------
if [[ ! -f "$SRV/run.sh" && ! -f "$SRV/.installed" ]]; then
  PACK_CACHE="gs://${BUCKET_NAME}/serverpack/atm11-${CURSEFORGE_FILE_ID}.zip"
  ZIP=/tmp/serverpack.zip

  if gsutil -q stat "$PACK_CACHE"; then
    log "server pack found in bucket cache, downloading"
    gsutil cp "$PACK_CACHE" "$ZIP"
  else
    log "fetching server pack from CurseForge (project=$CURSEFORGE_PROJECT_ID file=$CURSEFORGE_FILE_ID)"
    [[ -n "$CF_API_KEY" ]] || { log "ERROR: no CurseForge API key and no bucket cache"; exit 1; }
    URL=$(curl -fsSL -H "x-api-key: ${CF_API_KEY}" \
      "https://api.curseforge.com/v1/mods/${CURSEFORGE_PROJECT_ID}/files/${CURSEFORGE_FILE_ID}" \
      | jq -r '.data.downloadUrl')
    [[ "$URL" != "null" && -n "$URL" ]] || { log "ERROR: CurseForge returned no downloadUrl (distribution disabled?)"; exit 1; }
    curl -fsSL -o "$ZIP" "$URL"
    log "caching server pack to bucket"
    gsutil cp "$ZIP" "$PACK_CACHE"
  fi

  log "extracting server pack"
  unzip -oq "$ZIP" -d "$SRV"
  rm -f "$ZIP"
  # Some packs nest everything one level deep; flatten if so.
  if [[ ! -f "$SRV/run.sh" ]]; then
    inner=$(find "$SRV" -maxdepth 2 -name run.sh -printf '%h\n' | head -1 || true)
    [[ -n "$inner" ]] && cp -an "$inner"/. "$SRV"/
  fi
  touch "$SRV/.installed"
fi

# ---------------------------------------------------------------------------
# 4. Config: EULA, heap, server.properties (with RCON wired for clean backups)
# ---------------------------------------------------------------------------
echo "eula=true" > "$SRV/eula.txt"
sed "s/__JVM_HEAP__/${JVM_HEAP}/g" "$DEPLOY/config/user_jvm_args.txt" > "$SRV/user_jvm_args.txt"

cp "$DEPLOY/config/server.properties" "$SRV/server.properties"
{
  echo "server-port=${SERVER_PORT}"
  echo "enable-rcon=true"
  echo "rcon.port=25575"
  echo "rcon.password=${RCON_PASSWORD}"
} >> "$SRV/server.properties"

chown -R root:root /opt/minecraft

# ---------------------------------------------------------------------------
# 5. Restore the latest world backup (only if no world present yet)
# ---------------------------------------------------------------------------
"$DEPLOY/restore.sh" || log "restore step reported no backup to restore (fresh world)"

# ---------------------------------------------------------------------------
# 6. systemd: the server + the daily backup timer
# ---------------------------------------------------------------------------
log "installing systemd units"
cp "$DEPLOY/systemd/minecraft.service"        /etc/systemd/system/
cp "$DEPLOY/systemd/minecraft-backup.service" /etc/systemd/system/
cp "$DEPLOY/systemd/minecraft-backup.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now minecraft.service
systemctl enable --now minecraft-backup.timer

log "done — server starting. tail: journalctl -u minecraft -f"
