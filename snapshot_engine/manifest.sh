#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MANIFEST_ROOT="$SCRIPT_DIR/../blob_manifests"
OUT="$SCRIPT_DIR/../manifest.json"

RECURSE_BLOBS="$SCRIPT_DIR/recurse_blobs.sh"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd sha256sum
require_cmd jq

# ------------------------------------------------------------
# Arguments
# ------------------------------------------------------------

RUN_UPDATE=true

WORKING_BLOBS=""
ARCHIVED_BLOBS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-update)
      RUN_UPDATE=false
      shift
      ;;
    *)
      if [[ -z "$WORKING_BLOBS" ]]; then
        WORKING_BLOBS="$1"
      elif [[ -z "$ARCHIVED_BLOBS" ]]; then
        ARCHIVED_BLOBS="$1"
      else
        die "Too many arguments"
      fi
      shift
      ;;
  esac
done

if [[ "$RUN_UPDATE" == true ]]; then
  [[ -n "$WORKING_BLOBS" ]] || die "Missing <Blobs> argument"
  [[ -n "$ARCHIVED_BLOBS" ]] || die "Missing <Archived Blobs> argument"
fi

# ------------------------------------------------------------
# Phase 0: update blob manifests (optional)
# ------------------------------------------------------------

if [[ "$RUN_UPDATE" == true ]]; then
  [[ -x "$RECURSE_BLOBS" ]] || die "recurse_blobs.sh not executable"

  log "Updating blob manifests"
  log "  Blobs:          $WORKING_BLOBS"
  log "  Archived Blobs: $ARCHIVED_BLOBS"

  "$RECURSE_BLOBS" "$WORKING_BLOBS" "$ARCHIVED_BLOBS"
else
  log "Skipping blob manifest generation (--no-update)"
fi

# ------------------------------------------------------------
# Phase 1: aggregate blob manifests
# ------------------------------------------------------------

log "Aggregating blob manifests from $MANIFEST_ROOT"

find "$MANIFEST_ROOT" -type f -name '*.json' -print0 \
  | sort -z \
  | while IFS= read -r -d '' manifest; do

      # Validate JSON
      jq -e '.' "$manifest" >/dev/null 2>&1 || continue

      # Validate expected schema from blob.sh
      jq -e '
        .collection_id and
        .hash_algorithm and
        .blob.object and
        .blob.size_bytes and
        .blob.sha256
      ' "$manifest" >/dev/null || continue

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
