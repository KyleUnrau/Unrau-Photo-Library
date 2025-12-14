#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration (single source of truth) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOBS_PATH="${SCRIPT_DIR}/../../Blobs"
MANIFEST_PATH="${SCRIPT_DIR}/../Blob Manifests"
BLOB_GENERATOR="./blob_manifest.sh"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

# ---- Safety checks ----
die() {
  echo "ERROR: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found. Please install it."
}

# ---- Walk blobs and generate manifests ----

find "$BLOBS_PATH" -type f -name '*.zip' | LC_ALL=C sort | while read -r zip; do
  rel="${zip#$BLOBS_PATH/}"

  log "======= ${rel} ======="

  [[ "$rel" != "$zip" ]] || die "ZIP outside $BLOBS_PATH: $zip"

  out_dir="$MANIFEST_PATH/$(dirname "$rel")"
  out_file="$out_dir/$(basename "$rel" .zip).json"

  mkdir -p "$out_dir"

  chmod +x "${BLOB_GENERATOR}"
  bash "$BLOB_GENERATOR" "$rel" "$out_file"
done

log "Blob manifests updated successfully."