#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

die() {
  log "ERROR: $1"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

manifest_is_up_to_date() {
  local manifest="$1"
  local zip_size="$2"
  local zip_sha="$3"

  [[ -f "$manifest" ]] || return 1

  local man_size man_sha
  man_size=$(jq -r '.blob.size_bytes' "$manifest" 2>/dev/null) || return 1
  man_sha=$(jq -r '.blob.sha256' "$manifest" 2>/dev/null) || return 1

  [[ "$man_size" == "$zip_size" && "$man_sha" == "$zip_sha" ]]
}

require_cmd unzip
require_cmd sha256sum
require_cmd jq
require_cmd find
require_cmd stat
require_cmd readlink

# Resolve script directory robustly
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"

# Normalize project root
ROOT_DIRECTORY="$(cd "$SCRIPT_DIR/../.." && pwd)"

BLOB_FILE_PATH="${1:?Usage: $0 2001.zip}"
COLLECTION_ID="${BLOB_FILE_PATH%.zip}"

# Normalize blob path
BLOB="$(cd "$ROOT_DIRECTORY/Blobs" && pwd)/$BLOB_FILE_PATH"

# Blob path relative to project root (for manifest)
BLOB_ID_PATH="${BLOB#${ROOT_DIRECTORY}/}"

OUT="${2:-$SCRIPT_DIR/../Blob Manifest/${COLLECTION_ID}.json}"

log "Starting manifest generation"
log "Blob: $BLOB"
log "Output: $OUT"

log "Hashing blob"
BLOB_SIZE=$(stat -c %s "$BLOB")
BLOB_SHA256=$(sha256sum "$BLOB" | cut -d' ' -f1)

if manifest_is_up_to_date "$OUT" "$BLOB_SIZE" "$BLOB_SHA256"; then
  log "Manifest up-to-date, skipping ($COLLECTION_ID)"
  exit 0
fi

log "Manifest out of date, regenerating ($COLLECTION_ID)"

[[ -f "$BLOB" ]] || die "Blob not found: $BLOB"

TMP_DIR="$(mktemp -d)"
FILES_JSONL="$(mktemp)"

cleanup() {
  log "Cleaning up temporary directory"
  rm -rf "$TMP_DIR"
  rm -f "$FILES_JSONL"
}
trap cleanup EXIT

log "Extracting ZIP to temporary directory"
unzip -q "$BLOB" -d "$TMP_DIR"
log "Extraction complete"

log "Discovering files"

FILES_REL=()
while IFS= read -r -d '' rel; do
  FILES_REL+=("${rel#./}")
done < <(
  cd "$TMP_DIR" && find . -type f -print0 | LC_ALL=C sort -z
)

log "Found ${#FILES_REL[@]} files"

log "Hashing files"
for rel in "${FILES_REL[@]}"; do
  file="$TMP_DIR/$rel"
  file_size=$(stat -c %s "$file")
  file_sha256=$(sha256sum "$file" | cut -d' ' -f1)

  jq -cn \
    --arg path "$rel" \
    --argjson size_bytes "$file_size" \
    --arg sha256 "$file_sha256" \
    '{path:$path,size_bytes:$size_bytes,sha256:$sha256}' \
    >> "$FILES_JSONL"
done
log "File hashing complete"

OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"

log "Writing manifest JSON"
jq -n \
  --arg collection_id "$COLLECTION_ID" \
  --arg generated_at "$(date -u +%FT%TZ)" \
  --arg hash_algorithm "sha256" \
  --arg blob_path "$BLOB_ID_PATH" \
  --argjson blob_size "$BLOB_SIZE" \
  --arg blob_sha256 "$BLOB_SHA256" \
  --slurpfile files "$FILES_JSONL" \
  '{
    collection_id: $collection_id,
    generated_at: $generated_at,
    hash_algorithm: $hash_algorithm,
    blob: {
      path: $blob_path,
      size_bytes: $blob_size,
      sha256: $blob_sha256
    },
    files: ($files | sort_by(.path))
  }' > "$OUT"

log "Manifest written successfully"
log "Completed ($COLLECTION_ID, ${#FILES_REL[@]} files)"
