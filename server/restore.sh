#!/usr/bin/env bash
# Restore the latest world backup from GCS onto a fresh server. Safety first:
# it will NOT overwrite an existing local world — restore only happens when the
# server has no world yet (fresh VM / new disk). Exits 0 with a notice if there
# is nothing to restore or a world already exists.
set -euo pipefail

source /etc/minecraft/arsenal.env

SRV=/opt/minecraft/server
LATEST="gs://${BUCKET_NAME}/backups/world-latest.tar.zst"

log() { echo "[restore $(date -u +%H:%M:%S)] $*"; }

if [[ -d "$SRV/world" ]]; then
  log "world already present locally — skipping restore (won't clobber)"
  exit 0
fi

if ! gsutil -q stat "$LATEST"; then
  log "no backup in bucket — starting a brand-new world"
  exit 0
fi

log "restoring latest world from $LATEST"
tmp=/tmp/restore.tar.zst
gsutil cp "$LATEST" "$tmp"
zstd -dq "$tmp" -o /tmp/restore.tar
tar -C "$SRV" -xf /tmp/restore.tar
rm -f "$tmp" /tmp/restore.tar
log "world restored"
