# knowledge_base
A curated collection of notes, scripts, and references for system administration, Proxmox VE, and related tools.

---

## Table of Contents

- [Purpose](#purpose)
- [Repository structure](#repository-structure)
- [Notable scripts](#notable-scripts)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)
- [Contact](#contact)

---

## Purpose ✅

This repository collects useful snippets, documentation, and small utilities that I (or contributors) use for day-to-day systems administration, automation, and troubleshooting. It is intended as a lightweight personal knowledge base and toolbox.

## Repository structure 🔧

- `ProxmoxVE/` — Proxmox-related resources and scripts
  - `scripts/` — helper scripts and utilities

Example:

```
ProxmoxVE/
  └─ scripts/
      └─ proxmox_orphaned_backup_scanner.sh
```

## Notable scripts 💡

- `ProxmoxVE/scripts/proxmox_orphaned_backup_scanner.sh` — Scans Proxmox backup storage for files that appear to be orphaned (not associated with any current backup entries) and reports them for review. Read the script header and use `--help` if available for usage details.

## Usage 📋

General guidelines for running scripts:

1. Inspect the script before running: `less ProxmoxVE/scripts/proxmox_orphaned_backup_scanner.sh`
2. Make it executable and run it locally:

```bash
chmod +x ProxmoxVE/scripts/proxmox_orphaned_backup_scanner.sh
./proxmox_orphaned_backup_scanner.sh
```

or

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/angelizer369/knowledge_base/refs/heads/main/ProxmoxVE/scripts/proxmox_orphaned_backup_scanner.sh)"
```


Run scripts with appropriate privileges (e.g., via `sudo`) only when you understand their effects.

## Contributing 🤝

Contributions are welcome. Suggested workflow:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/foo`)
3. Make changes and add tests if applicable
4. Open a pull request with a clear description of your changes

If you spot issues or have enhancement ideas, please open an issue.

## License 📄

This project is licensed under the terms of the `LICENSE` file in this repository.

## Contact ✉️

If you have questions or suggestions, open an issue or send a PR — I review both when possible.

---

Thanks for checking out this repository! Feel free to suggest improvements or add more scripts and notes.
