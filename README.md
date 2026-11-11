# archiso

Reproducible CachyOS-based installation ISOs for two machines.

- **Desktop:** AMD Ryzen 9 9900X, CachyOS Zen4, x86-64-v4.
- **Laptop:** Intel Core i5-1135G7, CachyOS x86-64-v3.

Both ISOs install a shared MangoWM environment onto a whole disk: GPT, a 1 GiB
FAT32 EFI System Partition mounted at `/boot`, one ext4 root partition using all
remaining space, zram for swap. There is no separate `/home` partition, no LUKS,
no Btrfs and no snapshots.

## Status

Milestone 4 of 9 is complete. Everything below is planned, not yet implemented.

| Milestone | Scope | Status |
| --- | --- | --- |
| 1 | Repository initialization | done |
| 2 | Package inventory | done |
| 3 | CachyOS repository integration | done |
| 4 | System configuration | done |
| 5 | Dotfiles and user environment | pending |
| 6 | Secrets backup and restoration | pending |
| 7 | Installer implementation | pending |
| 8 | ISO generation | pending |
| 9 | Validation | pending |

## Layout

```text
common/     packages, dotfiles, system config, shared scripts
desktop/    desktop-only packages, pacman config, profile
laptop/     laptop-only packages, pacman config, profile
installer/  installation scripts
secrets/    encrypted secret backup tooling
iso/        Archiso profiles and build script
scripts/    repository maintenance scripts
output/     generated ISO artifacts (not tracked)
```

## Build

```bash
./iso/build.sh desktop
./iso/build.sh laptop
./iso/build.sh all
```

Expected artifacts:

```text
output/arch-desktop.iso
output/arch-desktop.iso.sha256
output/arch-laptop.iso
output/arch-laptop.iso.sha256
```

## Safety

Selecting a disk erases its partition table and all data. The installer never
selects a disk automatically and requires explicit confirmation of the selected
device.

Never commit secrets or generated ISO files.

## License

MIT. See `LICENSE`.
