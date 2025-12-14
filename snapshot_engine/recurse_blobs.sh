#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOB_GENERATOR="$SCRIPT_DIR/blob.sh"

WORKING_BLOBS="${1:?Usage: $0 <Blobs> <Archived Blobs>}"
ARCHIVED_BLOBS="${2:?Usage: $0 <Archived Blobs>}"

MANIFEST_ROOT="$SCRIPT_DIR/../blob_manifests"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

warn() {
  printf '[%s] WARNING: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
  exit 1
}

# ---- Safety checks ----
mkdir -p $MANIFEST_ROOT

[[ -d "$WORKING_BLOBS" ]] || die "Blobs directory not found: $WORKING_BLOBS"
[[ -d "$ARCHIVED_BLOBS" ]] || die "Archived Blobs directory not found: $ARCHIVED_BLOBS"
[[ -x "$BLOB_GENERATOR" ]] || die "blob.sh not executable"

WORKING_BLOBS="$(cd "$WORKING_BLOBS" && pwd)"
ARCHIVED_BLOBS="$(cd "$ARCHIVED_BLOBS" && pwd)"
MANIFEST_ROOT="$(cd "$MANIFEST_ROOT" && pwd)"

log "Working blobs:  $WORKING_BLOBS"
log "Archived blobs: $ARCHIVED_BLOBS"
log "Manifests:      $MANIFEST_ROOT"

# ------------------------------------------------------------------
# PHASE 1: discover all declared blobs (.blob markers)
# ------------------------------------------------------------------

log "PHASE 1/3: Discovering blob markers (.blob)"

BLOB_DIRS=()
while IFS= read -r marker; do
  blob_dir="$(dirname "$marker")"
  BLOB_DIRS+=("$blob_dir")
done < <(find "$WORKING_BLOBS" -type f -name '.blob' | LC_ALL=C sort)

log "Discovered ${#BLOB_DIRS[@]} blob(s)."

if ((${#BLOB_DIRS[@]} > 0)); then
  log "Blob list:"
  for blob_dir in "${BLOB_DIRS[@]}"; do
    rel="${blob_dir#$WORKING_BLOBS/}"
    log "  - $rel"
  done
else
  warn "No .blob markers found under: $WORKING_BLOBS"
fi

# ------------------------------------------------------------------
# PHASE 2: warn about suspicious unmarked directories
# ------------------------------------------------------------------

log "PHASE 2/3: Scanning for suspicious unmarked directories"

SUSPICIOUS=()
while IFS= read -r dir; do
  # Skip root
  [[ "$dir" == "$WORKING_BLOBS" ]] && continue

  # If this directory is inside a marked blob, skip it (blobs are atomic)
  # (We detect by checking if any .blob exists at/under this dir OR above it.)
  # Fast rule: if this dir has a descendant .blob, it's a container, not suspicious.
  if find "$dir" -type f -name '.blob' -print -quit | grep -q .; then
    continue
  fi

  # If this dir is within any already-marked blob, skip.
  # (String prefix check; safe because paths are absolute.)
  skip=0
  for blob_dir in "${BLOB_DIRS[@]}"; do
    case "$dir/" in
      "$blob_dir"/*) skip=1 ;;
    esac
    ((skip)) && break
  done
  ((skip)) && continue

  # Does it contain files other than .blob (and ignoring common junk)?
  if find "$dir" -type f \
      ! -name '.blob' \
      ! -name 'desktop.ini' \
      -print -quit | grep -q .; then
    rel="${dir#$WORKING_BLOBS/}"
    SUSPICIOUS+=("$rel")
  fi
done < <(find "$WORKING_BLOBS" -type d | LC_ALL=C sort)

if ((${#SUSPICIOUS[@]} > 0)); then
  warn "Found ${#SUSPICIOUS[@]} suspicious unmarked folder(s) that contain files:"
  for rel in "${SUSPICIOUS[@]}"; do
    warn "  - $rel"
  done
  warn "If any of these should be archived as blobs, add an empty '.blob' file inside them."
else
  log "No suspicious unmarked folders detected."
fi

# ------------------------------------------------------------------
# PHASE 3: run generator for each blob (verbose)
# ------------------------------------------------------------------

log "PHASE 3/3: Generating snapshots + manifests for marked blobs"

i=0
total=${#BLOB_DIRS[@]}

for blob_dir in "${BLOB_DIRS[@]}"; do
  i=$((i + 1))
  rel="${blob_dir#$WORKING_BLOBS/}"

  out_dir="$MANIFEST_ROOT/$(dirname "$rel")"
  out_file="$out_dir/$(basename "$rel").json"
  mkdir -p "$out_dir"

  log "[$i/$total] BEGIN blob: $rel"
  log "          folder:   $blob_dir"
  log "          archive:  $ARCHIVED_BLOBS"
  log "          manifest: $out_file"

  # Run generator; if it fails, fail fast so you notice immediately.
  log "Invoking generator..."
  bash "$BLOB_GENERATOR" "$blob_dir" "$ARCHIVED_BLOBS" "$out_file"
  log "Generator finished with exit code $?"

  log "[$i/$total] DONE  blob: $rel"
done

log "Blob recursion complete."
