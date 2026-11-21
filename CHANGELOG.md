# Changelog

## 1.0.2

- Add .NET channel(s) 11.0 (monthly update, 2026-11-21): newly supported major(s) per Microsoft's releases-index.
- Channels are only ever added, never removed; drop EOL ones by hand if Dahlia no longer targets them.

## 1.0.1

- Fix CI: replace `Write-Host` with `Write-Output`, use approved verb + named parameters in `install-dotnet.ps1`.
- Harden CI dry-run checks so they don't depend on the runner's installed SDKs.

## 1.0.0

- Initial installer: `install-dotnet.sh` (Linux/macOS) and `install-dotnet.ps1` (Windows).
- Installs SDK channels 8.0, 9.0 and 10.0 from `dotnet-versions.env` via Microsoft's `dotnet-install` scripts.
- Idempotent routine behavior: `--check`, `--dry-run`, `--channel`, `--install-dir`, `--yes`.
