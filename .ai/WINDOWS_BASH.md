# Windows Bash Setup

OpenCaw commands use Bash. On Windows, prefer Git Bash for native Windows filesystem performance; use WSL when Linux tool compatibility is more important.

The scaffold never installs software automatically. Run these commands from the repository root in PowerShell.

## Check for an existing provider

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "./commands/install-windows-bash.ps1"
```

## Install native Git Bash (recommended)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "./commands/install-windows-bash.ps1" -Provider GitBash -Install
```

## Install WSL Bash

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "./commands/install-windows-bash.ps1" -Provider WSL -Install
```

WSL installation can require elevation or a restart.

## Run the OpenCaw scaffold

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "./commands/install-windows-bash.ps1" -Provider GitBash -RunScaffold -ProjectRoot .
```

Linux and macOS should run `./commands/create-host-ai-scaffold.sh` directly; this Windows bootstrap is not needed there.
