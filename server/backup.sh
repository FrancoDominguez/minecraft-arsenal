#!/usr/bin/env bash
# Daily world backup -> GCS. Flushes saves cleanly over RCON first so the
# tarball is consistent, then re-enables autosave. Triggered by the systemd
# timer; lifecycle rules on the bucket prune old backups.
set -euo pipefail

source /etc/minecraft/arsenal.env
source /etc/minecraft/rcon.env   # RCON_PASSWORD

SRV=/opt/minecraft/server
RCON_PORT=25575
STAMP=$(date -u +%Y%m%d-%H%M%S)
ARCHIVE="/tmp/world-${STAMP}.tar.zst"

log() { echo "[backup $(date -u +%H:%M:%S)] $*"; }

# Minimal RCON client (avoids any external binary). Sends one command.
rcon() {
  python3 - "$1" <<'PY'
import socket, struct, sys, os
host, port = "127.0.0.1", 25575
pw = os.environ["RCON_PASSWORD"]; cmd = sys.argv[1]
def pkt(i, t, b): b=b.encode(); return struct.pack("<iii", len(b)+10, i, t)+b+b"\x00\x00"
s = socket.create_connection((host, port), 10)
s.sendall(pkt(1, 3, pw))  # auth
s.recv(4096)
s.sendall(pkt(2, 2, cmd)) # command
s.recv(4096)
s.close()
PY
}

cleanup() { RCON_PASSWORD="$RCON_PASSWORD" rcon "save-on" || true; }
trap cleanup EXIT

if systemctl is-active --quiet minecraft; then
  log "flushing world via RCON"
  RCON_PASSWORD="$RCON_PASSWORD" rcon "save-off"
  RCON_PASSWORD="$RCON_PASSWORD" rcon "save-all flush"
  sleep 5
fi

log "archiving world"
# Back up the world(s) only — mods/loader come from the pinned server pack.
tar -C "$SRV" -cf - world world_nether world_the_end 2>/dev/null \
  | zstd -q -3 -o "$ARCHIVE" || tar -C "$SRV" --warning=no-file-ignored -c world 2>/dev/null | zstd -q -3 -o "$ARCHIVE"

cleanup; trap - EXIT

log "uploading to gs://${BUCKET_NAME}/backups/"
gsutil cp "$ARCHIVE" "gs://${BUCKET_NAME}/backups/world-${STAMP}.tar.zst"
gsutil cp "$ARCHIVE" "gs://${BUCKET_NAME}/backups/world-latest.tar.zst"
rm -f "$ARCHIVE"

log "done"
