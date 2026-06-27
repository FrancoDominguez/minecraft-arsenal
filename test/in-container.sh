#!/usr/bin/env bash
# Runs INSIDE the test container. Reproduces what the GCE startup script does
# (write /etc/minecraft/arsenal.env, lay down the deploy/ dir), runs the real
# bootstrap.sh, then asserts the two things the live VM got wrong:
#   1. run.sh is generated (NeoForge --installServer ran)
#   2. the JVM actually launches past exec into mod-loading (no 203/EXEC)
set -uo pipefail
SRV=/opt/minecraft/server
log() { echo "[test $(date -u +%H:%M:%S)] $*"; }

# --- lay down deploy/ exactly like startup.sh.tpl does (rsync + chmod) ---
mkdir -p /opt/minecraft/deploy
cp -r /test/server/. /opt/minecraft/deploy/
chmod +x /opt/minecraft/deploy/*.sh

# --- runtime env the startup template normally renders from Terraform vars ---
mkdir -p /etc/minecraft
cat > /etc/minecraft/arsenal.env <<EOF
BUCKET_NAME=test-bucket
MINECRAFT_VERSION=${MINECRAFT_VERSION:-26.1.2}
NEOFORGE_VERSION=${NEOFORGE_VERSION:-26.1.2.76}
JAVA_VERSION=${JAVA_VERSION:-25}
JVM_HEAP=${JVM_HEAP:-3G}
SERVER_PORT=25565
CURSEFORGE_PROJECT_ID=${CURSEFORGE_PROJECT_ID:-0}
CURSEFORGE_FILE_ID=${CURSEFORGE_FILE_ID:-0}
CF_SECRET_ID=cf-key
RCON_SECRET_ID=rcon-pw
BACKUP_RETENTION_DAYS=7
EOF

log "running bootstrap.sh"
if ! /opt/minecraft/deploy/bootstrap.sh; then
  log "FAIL: bootstrap.sh exited non-zero"
  exit 1
fi

# --- assertion 1: run.sh exists & is executable ---
if [[ ! -x "$SRV/run.sh" ]]; then
  log "FAIL: $SRV/run.sh missing or not executable"
  ls -la "$SRV" | head -30
  exit 1
fi
log "PASS: run.sh present and executable"

# --- assertion 2: JVM launches and reaches mod-loading (light check) ---
TMO="${JVM_START_TIMEOUT:-240}"
log "launching server; will kill as soon as mod-loading begins (max ${TMO}s)"
cd "$SRV"
LOGF=/tmp/server.log
: > "$LOGF"
timeout "$TMO" bash run.sh nogui > "$LOGF" 2>&1 &
PID=$!

# A fatal pattern means the JVM/launcher died — must override any "progress"
# text, because error messages can themselves contain mod/package names.
FATAL='UnsupportedClassVersionError|has been compiled by a more recent version|LinkageError|Could not find or load main class|No such file or directory|203/EXEC|Exception in thread "main"|^Error:'
# Genuine forward-progress markers: these only print once FML is actually
# constructing/loading mods or the server is starting — NOT in error text.
SUCCESS='ModLauncher running:|Loading [0-9]+ mods|Constructing [0-9]+ mods|Loaded [0-9]+ mods|Preparing level|Starting minecraft server|Done \('

stop=0
for _ in $(seq 1 "$TMO"); do
  if grep -qiE "$FATAL" "$LOGF"; then stop=1; break; fi
  if grep -qE "$SUCCESS" "$LOGF"; then stop=1; break; fi
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
kill -TERM "$PID" 2>/dev/null
wait "$PID" 2>/dev/null

echo "----- last 25 lines of server log -----"
tail -n 25 "$LOGF"
echo "----------------------------------------"

# Fatal check wins regardless of what else is in the log.
if grep -qiE "$FATAL" "$LOGF"; then
  log "FAIL: JVM/launcher died — $(grep -oiE "$FATAL" "$LOGF" | head -1)"
  exit 1
fi
if grep -qE "$SUCCESS" "$LOGF"; then
  log "PASS: JVM launched and reached genuine mod-loading/startup"
  exit 0
fi
log "FAIL: no startup marker and no fatal error within ${TMO}s (JVM stalled?)"
exit 1
