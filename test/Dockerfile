# Local test image for bootstrap.sh — mirrors the GCE VM's OS (Debian 12) and
# bakes in the same Temurin 21 JDK + tools the bootstrap installs, so the image
# layer is cached and the test loop is fast. bootstrap.sh's Java guard sees Java
# already present and skips its apt step; everything after it runs for real.
#
# This is a LIGHT check: it validates the install/run path (does the NeoForge
# installer produce run.sh, does the JVM actually launch) with the GCP calls
# (Secret Manager, GCS) stubbed out. It does NOT exercise systemd or the bucket.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# Same package set as bootstrap.sh section 1, plus Temurin 25 from Adoptium
# (ATM11 / NeoForge 26.1.2.76 is compiled for Java 25 — class file version 69).
RUN apt-get update -y \
 && apt-get install -y wget apt-transport-https gpg unzip jq zstd ca-certificates python3 curl findutils \
 && mkdir -p /etc/apt/keyrings \
 && wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
      | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release; echo "$VERSION_CODENAME") main" \
      > /etc/apt/sources.list.d/adoptium.list \
 && apt-get update -y \
 && apt-get install -y temurin-25-jdk \
 && rm -rf /var/lib/apt/lists/*

# Stubbed gcloud/gsutil go first on PATH so bootstrap's GCP calls are intercepted.
COPY stubs/gcloud stubs/gsutil /usr/local/bin/
RUN chmod +x /usr/local/bin/gcloud /usr/local/bin/gsutil

ENTRYPOINT ["/bin/bash"]
