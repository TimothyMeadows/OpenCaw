# Windows Bash bootstrap and scaffold guidance

## Status
Archived on 20260726T015606Z.

## Archive
- /mnt/c/Repository/OpenCaw/.ai/archive/tasks/windows-bash-bootstrap-20260726T015606Z.md

## Durable Summary
- Goal: Provide a Windows-first bootstrap that can discover or explicitly install a usable Bash runtime and then invoke the existing OpenCaw scaffold, while leaving Linux and macOS behavior unchanged.
- Review: `commands/install-windows-bash.ps1` prefers native Git Bash, supports explicit `winget` Git installation or `wsl.exe --install`, and never installs without `-Install`.
