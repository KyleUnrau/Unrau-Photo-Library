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

require_cmd jq
require_cmd sha256sum
require_cmd find
require_cmd stat
require_cmd zip
require_cmd readlink

# ---------- arguments ----------
FOLDER="${1:?Usage: $0 <folder> <archive_dir> [manifest.json]}"
ARCHIVE_DIR="${2:?Usage: $0 <folder> <archive_dir> [manifest.json]}"
MANIFEST="${3:-$(basename "$FOLDER").json}"

[[ -d "$FOLDER" ]] || die "Folder not found: $FOLDER"
mkdir -p "$ARCHIVE_DIR"

COLLECTION_ID="$(basename "$FOLDER")"

# ---------- fast structural check ----------
blob_is_up_to_date() {
  local folder="$1"
  local manifest="$2"

  [[ -f "$manifest" ]] || return 1

  find "$folder" -type f ! -name '.blob' -printf '%P\t%s\n' | LC_ALL=C sort > /tmp/folder.$$
  jq -r '.files[] | "\(.path)\t\(.size_bytes)"' "$manifest" \
    | LC_ALL=C sort > /tmp/manifest.$$

  diff -q /tmp/folder.$$ /tmp/manifest.$$
  local rc=$?

  rm -f /tmp/folder.$$ /tmp/manifest.$$
  return $rc
}

if blob_is_up_to_date "$FOLDER" "$MANIFEST"; then
  log "Folder unchanged; skipping snapshot"
  exit 0
fi

log "Folder changed; creating new snapshot"

# ---------- create ZIP snapshot ----------
TMP_ZIP_DIR="$(mktemp -d)"
TMP_ZIP="$TMP_ZIP_DIR/snapshot.zip"

(
  cd "$FOLDER"
  zip -rq "$TMP_ZIP" . -x 'desktop.ini' -x '*/desktop.ini' -x '.blob'
)

ZIP_SHA256="$(sha256sum "$TMP_ZIP" | awk '{print $1}')"
ZIP_SIZE="$(stat -c %s "$TMP_ZIP")"
ZIP_PATH="$ARCHIVE_DIR/$ZIP_SHA256.zip"

if [[ ! -f "$ZIP_PATH" ]]; then
  cp "$TMP_ZIP" "$ZIP_PATH"
  rm -f "$TMP_ZIP"
  log "Stored snapshot: $ZIP_PATH"
else
  log "Snapshot already exists: $ZIP_PATH"
fi

# ---------- hash folder files ----------
FILES_JSONL="$(mktemp)"

while IFS= read -r -d '' file; do
  rel="${file#$FOLDER/}"
  size="$(stat -c %s "$file")"
  sha="$(sha256sum "$file" | awk '{print $1}')"

  jq -cn \
    --arg path "$rel" \
    --argjson size_bytes "$size" \
    --arg sha256 "$sha" \
    '{path:$path,size_bytes:$size_bytes,sha256:$sha256}' \
    >> "$FILES_JSONL"
done < <(
  find "$FOLDER" -type f \
    ! -name '.blob' \
    ! -name 'desktop.ini' \
    ! -name 'Thumbs.db' \
    ! -name '.DS_Store' \
    -print0 | LC_ALL=C sort -z
)

# ---------- write manifest ----------
mkdir -p "$(dirname -- "$MANIFEST")"

jq -n \
  --arg collection_id "$COLLECTION_ID" \
  --arg generated_at "$(date -u +%FT%TZ)" \
  --arg hash_algorithm "sha256" \
  --arg zip_object "$(basename "$ZIP_PATH")" \
  --argjson zip_size "$ZIP_SIZE" \
  --arg zip_sha "$ZIP_SHA256" \
  --slurpfile files "$FILES_JSONL" \
  '{
    collection_id: $collection_id,
    generated_at: $generated_at,
    hash_algorithm: $hash_algorithm,
    blob: {
      store: "blob-snapshots",
      object: $zip_object,
      size_bytes: $zip_size,
      sha256: $zip_sha
    },
    files: ($files | sort_by(.path))
  }' > "$MANIFEST"

rm -f "$FILES_JSONL"

log "Manifest written: $MANIFEST"
log "Completed snapshot for $COLLECTION_ID"