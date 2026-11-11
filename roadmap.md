# Arch/CachyOS Custom ISO — Revised Roadmap

## 1. Project goal

Create two independent, bootable installation ISOs:

- **Desktop:** CachyOS Zen4 / x86-64-v4 configuration.
- **Laptop:** CachyOS x86-64-v3 configuration.

Both ISOs will provide a reproducible, clean installation of the user's preferred system, including packages, configuration, dotfiles, and optional encrypted personal-secret restoration.

The installation must work from a Ventoy USB and install directly onto an explicitly selected whole disk.

## 2. Core decisions

### Installation and storage

- UEFI boot with GPT.
- Whole-disk installation, not installation into an existing partition.
- 1 GiB FAT32 EFI System Partition mounted at `/boot`.
- One ext4 root partition using all remaining disk space.
- No separate `/home` partition.
- No LUKS or other disk encryption.
- No Btrfs, Snapper, snapshots, or snapshot management.
- zram for swap; no swap partition.
- `noatime` mount option.

The installer must clearly warn that selecting a disk will erase its existing partition table and all data. Require the user to select the disk and explicitly confirm the destructive operation. Never select a disk automatically.

### Performance priorities

- Prioritize low latency, responsiveness, and minimal overhead.
- Use the appropriate CachyOS optimized repositories and kernel builds.
- Avoid unnecessary services and background processes.
- Avoid unnecessary filesystem layers and storage-management complexity.
- Do not introduce performance tweaks without a measurable justification.
- Preserve hardware-specific configuration.

### Desktop profile

- CachyOS Zen4 / x86-64-v4 repositories.
- `linux-cachyos-bore` (LTO build) appropriate to the desktop architecture.
- AMD microcode and AMD graphics stack (RADV).

### Laptop profile

- CachyOS x86-64-v3 repositories.
- `linux-cachyos-bore` (LTO build) appropriate to the laptop architecture.
- Intel microcode and Intel graphics stack (ANV).

### Shared environment

Maintain common packages and configuration for both systems, including:

- MangoWM, Waybar, Rofi, Mako.
- Fish, Fisher, Kitty, Neovim.
- Git, Go, Rust, LLVM/Clang, CMake, Ninja.
- PipeWire and common desktop utilities.
- Fonts, networking tools, and development utilities.

Keep hardware-specific packages and settings in their respective profiles.

### Networking

- Desktop uses `systemd-networkd` and `systemd-resolved` over its wired
  Realtek RTL8125 NIC. The desktop does not use Wi-Fi.
- Laptop uses NetworkManager.
- No `iwd`, Bluetooth manager or other network manager is installed.

## 3. Repository structure

```text
arch-config/
├── README.md
├── AGENTS.md
├── LICENSE
├── .gitignore
├── common/
│   ├── packages.txt
│   ├── aur-packages.txt
│   ├── dotfiles/
│   ├── system/
│   └── scripts/
├── desktop/
│   ├── packages.txt
│   ├── aur-packages.txt
│   ├── pacman.conf
│   └── profile/
├── laptop/
│   ├── packages.txt
│   ├── aur-packages.txt
│   ├── pacman.conf
│   └── profile/
├── installer/
│   ├── install.sh
│   ├── partition.sh
│   ├── packages.sh
│   ├── configure.sh
│   ├── dotfiles.sh
│   └── restore-secrets.sh
├── secrets/
│   ├── README.md
│   └── backup.sh
├── iso/
│   ├── build.sh
│   ├── common/
│   ├── desktop/
│   └── laptop/
├── scripts/
│   ├── inventory.sh
│   ├── validate.sh
│   └── clean.sh
└── output/
    └── .gitkeep
```

## 4. Installation workflow

1. Boot the selected ISO through Ventoy.
2. Select the target installation profile if not already determined by the ISO.
3. Establish network connectivity.
4. Display available disks and their sizes.
5. Require explicit whole-disk selection.
6. Display the selected disk and a destructive-operation warning.
7. Require explicit confirmation.
8. Create a GPT partition table.
9. Create and format the EFI and ext4 root partitions.
10. Install the base system and profile-specific packages.
11. Install and configure the appropriate CachyOS kernel and bootloader.
12. Apply system settings, services, and dotfiles.
13. Optionally restore personal secrets from the encrypted backup.
14. Generate the boot configuration and finish installation.

No destructive operation may occur before explicit confirmation.

## 5. Secrets backup and restoration

Use an encrypted archive stored separately on the Ventoy USB.

Include:
- GPG private/public keys and trust information.
- SSH private/public keys.
- gopass password store.

Requirements:
- Never store plaintext secrets in Git or ISO files.
- Require a passphrase to decrypt the archive.
- Never print secrets or passphrases in logs.
- Test restoration with disposable credentials.

Disk encryption and secrets-backup encryption are separate concerns: the system disk remains unencrypted.

## 6. Development milestones

### Milestone 1 — Repository initialization
- Create repository structure.
- Add README and AGENTS.md.
- Add initial documentation.
- No host modifications or package installation.

### Milestone 2 — Package inventory
- Inspect the existing package inventory.
- Categorize common, desktop, laptop, and AUR packages.
- Identify unnecessary packages and dependencies.
- Do not remove anything from the host.

### Milestone 3 — CachyOS repository integration
- Configure separate desktop and laptop pacman repositories.
- Verify repository signatures and architecture compatibility.
- Verify availability of the selected kernel packages.

### Milestone 4 — System configuration
- Implement common and hardware-specific configuration.
- Configure boot, services, networking, audio, graphics, and zram.
- Apply the minimal-performance-oriented system configuration.
- Exclude Snapper, snapshot services, LUKS, and Btrfs configuration.

### Milestone 5 — Dotfiles and user environment
- Integrate the selected dotfiles.
- Configure Fish, Fisher, Kitty, MangoWM, Waybar, and related applications.
- Keep configuration reproducible and version-controlled.

### Milestone 6 — Secrets backup and restoration
- Implement encrypted backup and restoration.
- Validate using disposable credentials.
- Ensure no secrets enter Git or ISO images.

### Milestone 7 — Installer implementation
- Implement disk discovery and explicit disk selection.
- Implement whole-disk GPT partitioning and ext4 formatting.
- Implement package installation and system configuration.
- Add safeguards against accidental disk erasure.

### Milestone 8 — ISO generation
- Build desktop and laptop ISOs using Archiso.
- Include the installer and required live-environment tools.
- Generate SHA256 checksums.
- Keep generated ISO artifacts out of Git.

### Milestone 9 — Validation
- Test both ISOs in disposable VMs.
- Test booting through Ventoy.
- Verify partitioning, package installation, bootloader, networking, and configuration.
- Test secret restoration.
- Document any hardware-specific limitations.

## 7. Build commands

```bash
./iso/build.sh desktop
./iso/build.sh laptop
./iso/build.sh all
```

Expected output:

```text
output/
├── arch-desktop.iso
├── arch-desktop.iso.sha256
├── arch-laptop.iso
└── arch-laptop.iso.sha256
```

## 8. Safety requirements

- Never modify the developer's running host installation.
- Never repartition or format real disks during development.
- Never assume a disk device name or select a disk based on size.
- Require explicit confirmation before any destructive installation action.
- Test installation logic in disposable VMs first.
- Never commit secrets or generated ISO files.
- Complete one milestone at a time and wait for user approval before continuing.
