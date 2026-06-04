# Proxmox VE Scripts

This directory contains shell scripts for automating Proxmox VE maintenance tasks.

## Requirements

Run these scripts from a Proxmox VE node as a user with sufficient privileges, normally `root`.

Common dependencies:

- `bash`
- `jq`
- `pvesh`
- `pvesm`
- standard Unix tools such as `awk`, `grep`, `sed`, `sort`, `wc`

Some scripts also require:

- `curl` for the web menu
- `bc` for size calculations
- `ssh` for cluster-wide rescans

## Safety notes

Some scripts can migrate disks or delete unused/orphaned volumes/backups. Review the displayed actions carefully and keep recent backups/snapshots before running destructive operations.

For convenience, examples below use `bash -c "$(curl ...)"`. For safer production use, download the script first, inspect it, then run it locally. Pinning a known commit URL is safer than running directly from the moving `main` branch.

## Scripts

### `proxmox__scripts_main_menu.sh`

Dynamically lists and runs all shell scripts in this folder from GitHub.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/angelizer369/knowledge_base/refs/heads/main/ProxmoxVE/scripts/proxmox__scripts_main_menu.sh)"
```

### `proxmox_migrate_disks_to_storage.sh`

Migrates selected VM/CT disks from one Proxmox storage to another using `pvesh`. Interactive confirmations default to **No**; bulk mode auto-confirms the selected scope.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/angelizer369/knowledge_base/refs/heads/main/ProxmoxVE/scripts/proxmox_migrate_disks_to_storage.sh)"
```

### `proxmox_orphaned_backup_scanner.sh`

Scans backup storages for backup files whose VMID/CTID no longer exists in the cluster. Deletion prompts default to **No**.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/angelizer369/knowledge_base/refs/heads/main/ProxmoxVE/scripts/proxmox_orphaned_backup_scanner.sh)"
```

### `proxmox_orphaned_disks_scanner.sh`

Scans VM/CT configs for `unusedX:` disk entries, displays them grouped by node and guest, and offers safe deletion prompts. Interactive deletion defaults to **No**.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/angelizer369/knowledge_base/refs/heads/main/ProxmoxVE/scripts/proxmox_orphaned_disks_scanner.sh)"
```

---

## Disclaimer

The information and scripts in this repository are provided "as is" and for educational purposes only. I am not responsible for any damage or loss that may occur from using them. Use at your own risk.
