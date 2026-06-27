#!/usr/bin/env bash
# Local "light check" for the server scripts: builds a Debian+JDK21 image, feeds
# it the real ATM11 server pack, runs the real bootstrap.sh with the GCP calls
# stubbed, and asserts run.sh is generated and the JVM launches. No GCP, no VM.
#
# Usage:  test/run-light-check.sh
# Reads CurseForge creds from $REPO/.env or ../minecraft-arsenal/.env (TF_VAR_*),
# or from env. The downloaded pack is cached under test/.cache/ (gitignored).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CACHE="$HERE/.cache"
mkdir -p "$CACHE"

# Resolve CurseForge params (env wins, then a .env file).
for envf in "$ROOT/.env" "$ROOT/../minecraft-arsenal/.env"; do
  if [[ -f "$envf" ]]; then set -a; # shellcheck disable=SC1090
    source "$envf"; set +a; break; fi
done
CF_KEY="${TF_VAR_curseforge_api_key:-${CF_API_KEY:-}}"
PROJ="${TF_VAR_curseforge_project_id:-${CURSEFORGE_PROJECT_ID:-1148445}}"
FILE="${TF_VAR_curseforge_server_file_id:-${CURSEFORGE_FILE_ID:-8304510}}"

ZIP="$CACHE/serverpack-$FILE.zip"
if [[ ! -f "$ZIP" ]]; then
  echo "[host] pack for file $FILE not cached — downloading from CurseForge"
  [[ -n "$CF_KEY" ]] || { echo "[host] ERROR: need TF_VAR_curseforge_api_key (or a .env) to download"; exit 1; }
  URL=$(curl -fsSL -H "x-api-key: $CF_KEY" "https://api.curseforge.com/v1/mods/$PROJ/files/$FILE" | jq -r '.data.downloadUrl')
  [[ "$URL" != "null" && -n "$URL" ]] || { echo "[host] ERROR: CurseForge returned no downloadUrl"; exit 1; }
  curl -fsSL -o "$ZIP" "$URL"
fi
echo "[host] pack: $ZIP ($(du -h "$ZIP" | cut -f1))"

echo "[host] building test image"
docker build -t mc-arsenal-test "$HERE"

echo "[host] running light check (this pulls NeoForge libs on first run; be patient)"
docker run --rm \
  -v "$ROOT/server:/test/server:ro" \
  -v "$ZIP:/test/serverpack.zip:ro" \
  -v "$HERE/in-container.sh:/test/in-container.sh:ro" \
  -e CURSEFORGE_PROJECT_ID="$PROJ" \
  -e CURSEFORGE_FILE_ID="$FILE" \
  -e JVM_HEAP="${JVM_HEAP:-3G}" \
  -e JVM_START_TIMEOUT="${JVM_START_TIMEOUT:-240}" \
  --memory=6g \
  mc-arsenal-test /test/in-container.sh
