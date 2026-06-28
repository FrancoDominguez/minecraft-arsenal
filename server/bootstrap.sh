#!/usr/bin/env bash
# First-boot installer for the All the Mods 10 server. Idempotent: safe to
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

# SSH quality-of-life tools, installed independently of the Java guard above so
# they show up even on a VM that already had Java. Runs its own apt-get update so
# it doesn't depend on the Java block above having refreshed the package lists
# (which it skips when Java is already present — e.g. a reboot).
if ! command -v nvim >/dev/null || ! command -v tmux >/dev/null; then
  log "installing neovim + tmux"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y neovim tmux
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
# 3a. Extract the ATM10 server pack (once — gated by the .installed sentinel).
# ---------------------------------------------------------------------------
if [[ ! -f "$SRV/.installed" ]]; then
  PACK_CACHE="gs://${BUCKET_NAME}/serverpack/${CURSEFORGE_PROJECT_ID}-${CURSEFORGE_FILE_ID}.zip"
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
  # Some packs nest everything one level deep; flatten if so. Look for either a
  # ready run.sh or the NeoForge installer (the pack ships the latter).
  if [[ ! -f "$SRV/run.sh" ]] && ! compgen -G "$SRV/neoforge-*-installer.jar" >/dev/null; then
    inner=$(find "$SRV" -maxdepth 2 \( -name run.sh -o -name 'neoforge-*-installer.jar' \) -printf '%h\n' | head -1 || true)
    [[ -n "$inner" && "$inner" != "$SRV" ]] && cp -an "$inner"/. "$SRV"/
  fi
  touch "$SRV/.installed"
fi

# ---------------------------------------------------------------------------
# 3b. Ensure run.sh exists. Kept SEPARATE from extraction (not gated by
# .installed) so a half-installed disk — pack extracted but run.sh never
# generated, e.g. an earlier boot that died here — self-heals on the next run.
#
# NeoForge server packs (ATM10) DON'T ship a ready-to-run run.sh; they ship the
# NeoForge installer + startserver.sh. run.sh (plus the libraries/ tree and the
# @argfiles `run.sh nogui` depends on) is produced by the installer's
# --installServer step.
# ---------------------------------------------------------------------------
if [[ ! -f "$SRV/run.sh" ]]; then
  installer=$(find "$SRV" -maxdepth 1 -name 'neoforge-*-installer.jar' | head -1 || true)
  [[ -n "$installer" ]] || { log "ERROR: no run.sh and no NeoForge installer in $SRV"; exit 1; }
  log "generating run.sh via NeoForge installer ($(basename "$installer"))"
  ( cd "$SRV" && java -jar "$installer" --installServer )
fi
[[ -f "$SRV/run.sh" ]] || { log "ERROR: NeoForge --installServer did not produce run.sh"; exit 1; }
chmod +x "$SRV/run.sh"

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
# 5b. Seed FTB Ranks. Runs after restore so a restored world's existing
# ranks.snbt is preserved; only fresh worlds get our seed. The `member` rank
# grants ftbchunks.chunk_load_offline so force-loaded chunks keep ticking
# when no players are online (iron farms, etc.).
# ---------------------------------------------------------------------------
mkdir -p "$SRV/world/serverconfig/ftbranks"
if [[ ! -f "$SRV/world/serverconfig/ftbranks/ranks.snbt" ]]; then
  cp "$DEPLOY/config/ftbranks/ranks.snbt" "$SRV/world/serverconfig/ftbranks/ranks.snbt"
  log "seeded world/serverconfig/ftbranks/ranks.snbt"
fi

# ---------------------------------------------------------------------------
# 6. systemd: the server + the daily backup timer
# ---------------------------------------------------------------------------
# Skipped when there's no systemd (e.g. the local Docker test harness, which
# runs bootstrap.sh directly and then launches run.sh itself).
if [[ -d /run/systemd/system ]]; then
  log "installing systemd units"
  cp "$DEPLOY/systemd/minecraft.service"        /etc/systemd/system/
  cp "$DEPLOY/systemd/minecraft-backup.service" /etc/systemd/system/
  cp "$DEPLOY/systemd/minecraft-backup.timer"   /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now minecraft.service
  systemctl enable --now minecraft-backup.timer
  log "done — server starting. tail: journalctl -u minecraft -f"
else
  log "no systemd detected (local test) — skipping unit install; run.sh is ready"
fi
