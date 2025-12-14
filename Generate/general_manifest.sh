#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_ROOT="$SCRIPT_DIR/../Blob Manifests"
OUT="$SCRIPT_DIR/../manifest.json"

ALL_BLOB_GENERATE="${SCRIPT_DIR}/all_blob_manifests.sh"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found. Please install it."
}

require_cmd sha256sum
require_cmd jq


RUN_UPDATE=true

case "${1:-}" in
  --no-update)
    RUN_UPDATE=false
    ;;
  "" )
    ;;
  *)
    echo "ERROR: Unknown option: $1" >&2
    echo "Usage: $0 [--no-blobs]" >&2
    exit 1
    ;;
esac

if [[ "$RUN_UPDATE" == true ]]; then
  chmod +x "${ALL_BLOB_GENERATE}"
  bash "${ALL_BLOB_GENERATE}"
else
  log "Skipping blob manifest generation (--no-blobs)"
fi


# Emit one JSON object per blob manifest, then slurp them
find "$MANIFEST_ROOT" -type f -print0 \
  | sort -z \
  | while IFS= read -r -d '' manifest; do

      case "$manifest" in
        *.json) ;;
        *) continue ;;
      esac

      # Must be valid JSON
      if ! jq -e '.' "$manifest" >/dev/null 2>&1; then
        continue
      fi

      # Validate schema
      jq -e '
        .collection_id and
        .hash_algorithm and
        .blob.path and
        .blob.size_bytes and
        .blob.sha256
      ' "$manifest" >/dev/null

      manifest_path="${manifest#$MANIFEST_ROOT/}"
      manifest_sha256="$(sha256sum "$manifest" | awk '{print $1}')"

      jq -c \
        --arg manifest_path "$manifest_path" \
        --arg manifest_sha256 "$manifest_sha256" \
        '{
          collection_id: .collection_id,
          blob: .blob,
          manifest: {
            path: $manifest_path,
            sha256: $manifest_sha256
          }
        }' "$manifest"

    done \
| jq -s '
  {
    schema_version: 1,
    library: "family-photo-archive",
    generated_at: (now | todate),
    hash_algorithm: "sha256",
    collections: .
  }
' > "$OUT"

log "Wrote $OUT"
