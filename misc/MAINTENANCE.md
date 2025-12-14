# Maintenance Guide

This document describes how the **snapshot engine** is operated and maintained.
The system is no longer a passive manifest generator — it is a **snapshotting system for a live photo library**, with explicit rules for what is and is not considered part of the archive.

---

## Required Tools (Ubuntu / WSL)

The snapshot engine relies on standard Unix tools.

Required:

* `sha256sum` (coreutils)
* `jq`
* GNU userland (`find`, `sort`, `awk`)

Install:

```bash
sudo apt-get update
sudo apt-get install -y coreutils jq
```

The scripts fail fast if dependencies are missing.

---

## Google Drive + WSL Setup

If the photo library lives on Google Drive mounted via Windows:

```bash
sudo mkdir -p /mnt/google
sudo mount -t drvfs G: /mnt/google -o metadata
```

Notes:

* `metadata` is required for permissions and executables
* Performance is slower than native Linux
* Large snapshots will take time
* Interrupting is safe; reruns are deterministic

---

## Repository Structure

```
.
├── README.md
├── blob_manifests/          # Generated JSON snapshots (one per blob)
│   ├── 2000.json
│   ├── 2002.json
│   └── ...
├── misc/
│   ├── MAINTENANCE.md       # This file
│   └── reference images
└── snapshot_engine/
    ├── blob.sh              # Snapshot a single blob directory
    ├── recurse_blobs.sh     # Discover blobs and invoke blob.sh
    └── manifest.sh          # Orchestrates snapshot + aggregation
```

**Everything under `blob_manifests/` is generated.**
Manual edits are invalid and will be overwritten.

---

## Conceptual Model (Read This)

The system operates on **directories**, not archives.

### Definitions

* **Blob**
  A directory that contains a `.blob` marker file.
  This directory is treated as an **atomic snapshot unit**.

* **Snapshot**
  A cryptographic description of:

  * all files under a blob directory
  * their sizes
  * their SHA-256 hashes
  * the blob’s identity and location

* **Global Manifest**
  A point-in-time index that records:

  * which blobs exist
  * which snapshot describes each blob
  * hashes of those snapshots

---

## Blob Discovery Rules (Non-Negotiable)

A directory is considered a blob **if and only if**:

* It contains a `.blob` file (empty is fine)

### Consequences

* A directory with photos **but no `.blob` file**:

  * is **not snapshotted**
  * **produces a warning**
  * is assumed to be accidental or unapproved

* A directory with `.blob`:

  * is snapshotted recursively
  * all files count, regardless of type

This design is deliberate.
Nothing is included by accident.

---

## The Role of `manifest.sh`

`manifest.sh` is the **entry point** for the snapshot engine.

It performs **two distinct phases**, unless explicitly told not to.

---

## Phase 0 — Snapshot Generation (Optional)

Triggered unless `--no-update` is passed.

### What happens

* Recursively scans:

  * **Working library root** (live photo folders)
  * **Archived snapshot root** (previous snapshots)
* Discovers directories marked with `.blob`
* Emits or updates one JSON snapshot per blob under `blob_manifests/`

### What it snapshots

For each blob directory:

* Relative path
* File list (recursive)
* File sizes
* SHA-256 hash of every file
* Aggregate metadata

### What it does *not* do

Facts:

* Does **not** move files
* Does **not** modify photos or videos
* Does **not** copy data into the repository
* Does **not** delete old snapshots

It measures. It records. Nothing else.

This phase is implemented by `recurse_blobs.sh` → `blob.sh`.

---

## Phase 1 — Manifest Aggregation (Always Runs)

This phase **always executes**, even with `--no-update`.

### What happens

* Reads all valid JSON files in `blob_manifests/`
* Rejects malformed or incomplete snapshots
* Hashes each snapshot file itself
* Emits a single `manifest.json` that represents:

  * the full snapshot state
  * at a specific point in time

If this completes successfully, `manifest.json` is authoritative.

---

## Invocation

### Normal usage (recommended)

```bash
./manifest.sh \
  "/mnt/google/My Drive/Family/Photos/Library/" \
  "/mnt/google/My Drive/Family/Photos/Blob Snapshots/"
```

Meaning:

1. Snapshot the live photo library
2. Incorporate archived blobs
3. Regenerate `manifest.json`

This is the **canonical maintenance command**.

---

### Aggregation only (no filesystem scanning)

```bash
./manifest.sh --no-update
```

Use this **only** when:

* You know snapshots are already correct
* You want to rebuild `manifest.json` deterministically

This will fail if required arguments are missing **unless** `--no-update` is used.

---



## Outputs

### `blob_manifests/*.json`

Each file represents **one blob snapshot**.

Properties:

* Deterministic
* Regenerated when blob contents change
* Hash changes indicate real filesystem changes

---

### `manifest.json`

This is the **snapshot of snapshots**.

It records:

* Snapshot schema version
* Generation timestamp (UTC)
* Hash algorithm
* One entry per blob:

  * blob metadata
  * snapshot path
  * snapshot SHA-256

Integrity rule:

> If `manifest.json` and all referenced blob snapshots match disk, the library state is exactly known.

Anything else is drift.

---

## Warnings, Failures, and Drift

Be precise:

* New files → snapshot hash changes
* Deleted files → snapshot hash changes
* Unmarked photo directories → warnings
* Deleted blobs → disappear from manifest
* Invalid snapshot JSON → ignored silently

There is no attempt to infer intent.

---

## Maintenance Philosophy

This system is intentionally strict.

* Inclusion requires intent (`.blob`)
* History is preserved via snapshots
* Measurement beats mutation
* Hashes beat trust

If something looks wrong, **fix the filesystem**, then rerun the snapshot engine.

Never edit generated artifacts by hand.
