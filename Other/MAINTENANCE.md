## Repository Structure

```
Manifest/
├── Blob Manifests/      # One JSON file per archive (ZIP)
├── Generate/            # Scripts that create/update manifests
├── manifest.json        # Global index of all archives
└── README.md            # This file
```

### Blob Manifests

Each file in `Blob Manifests/` describes **one ZIP archive**:

* Where it lives
* How big it is
* Its cryptographic hash
* A complete list of contained files and their hashes

### Global Manifest (`manifest.json`)

This is the **master index**.
It lists:

* Every archive
* Where it is stored
* Which blob manifest describes it
* A hash of each blob manifest

If `manifest.json` and all blob manifests match reality, the library is intact.

---

## Technical Section

### Required tools (Ubuntu / WSL)

Ensure these tools exist:

* `unzip`
* `sha256sum`
* `jq`

Install:

```bash
sudo apt-get update
sudo apt-get install -y unzip coreutils jq
```

---

### Generate or update manifests

From WSL / Linux:

```bash
cd /mnt/g/My\ Drive/Family/Canonical\ Photo\ Library/Manifest/Generate
bash ./general_manifest.sh
```

What this does:

* Generates or updates **each blob manifest**
* Generates or updates the **global manifest (`manifest.json`)**
* Does **not** modify ZIP files

Sit back and wait — large archives take time.

---