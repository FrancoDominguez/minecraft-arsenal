#!/usr/bin/env bash
# Rendered by Terraform and run by GCE on every boot. Intentionally tiny:
# it writes runtime config, pulls the git-versioned scripts from the bucket,
# and hands off to bootstrap.sh. All real logic lives in server/bootstrap.sh.
set -euo pipefail
exec > >(tee -a /var/log/minecraft-bootstrap.log) 2>&1
echo "=== startup $(date -u) ==="

# Non-secret runtime config. Secrets are fetched from Secret Manager in bootstrap.
mkdir -p /etc/minecraft
cat > /etc/minecraft/arsenal.env <<EOF
BUCKET_NAME=${bucket_name}
MINECRAFT_VERSION=${minecraft_version}
NEOFORGE_VERSION=${neoforge_version}
JAVA_VERSION=${java_version}
JVM_HEAP=${jvm_heap}
SERVER_PORT=${server_port}
CURSEFORGE_PROJECT_ID=${curseforge_project_id}
CURSEFORGE_FILE_ID=${curseforge_file_id}
CF_SECRET_ID=${cf_secret_id}
RCON_SECRET_ID=${rcon_secret_id}
BACKUP_RETENTION_DAYS=${backup_retention_days}
EOF

# gsutil ships on Debian GCE images via the Google Cloud SDK.
mkdir -p /opt/minecraft/deploy
gsutil -m rsync -r -d "gs://${bucket_name}/deploy" /opt/minecraft/deploy
chmod +x /opt/minecraft/deploy/*.sh
exec /opt/minecraft/deploy/bootstrap.sh
