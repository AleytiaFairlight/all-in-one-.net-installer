# Changelog

## 1.0.0

- Initial installer: `install-dotnet.sh` (Linux/macOS) and `install-dotnet.ps1` (Windows).
- Installs SDK channels 8.0, 9.0 and 10.0 from `dotnet-versions.env` via Microsoft's `dotnet-install` scripts.
- Idempotent routine behavior: `--check`, `--dry-run`, `--channel`, `--install-dir`, `--yes`.
