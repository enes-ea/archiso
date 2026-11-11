# AGENTS.md

## Project Overview

This repository builds two automated, reproducible CachyOS-based Arch Linux installation ISOs:

- **Desktop:** AMD Ryzen 9 9900X, CachyOS Zen4, x86-64-v4.
- **Laptop:** Intel Core i5-1135G7, CachyOS x86-64-v3.

Both installations share a common desktop environment, packages, dotfiles and configuration, with hardware-specific differences.

The primary objective is to create bootable installation media that can reproduce the user's preferred Arch Linux environment without manually configuring packages, drivers or desktop settings.

Read `README.md` before making changes.

---

## 1. Working Rules

1. Work on exactly one milestone at a time.
2. Do not start another milestone without explicit user confirmation.
3. Inspect the existing repository before modifying anything.
4. Prefer simple, maintainable solutions over unnecessary abstractions.
5. Do not introduce dependencies without a clear justification.
6. Do not make assumptions about CachyOS repository names, package availability or architecture compatibility. Verify them.
7. Do not silently change established project decisions.
8. Keep changes focused on the current task.
9. Do not overwrite existing user files without permission.
10. Report blockers instead of implementing speculative workarounds.

## 2. Safety Rules

This project involves automated disk installation. Safety is mandatory.

### Disk operations

- Never execute destructive disk operations on the development machine.
- Never format, repartition or erase a disk during development.
- Never hardcode disk identifiers such as `/dev/nvme0n1`.
- Never automatically select a disk based solely on its size.
- Require explicit target-disk confirmation before destructive installation.
- Display the selected disk, partitions and expected consequences before confirmation.
- Refuse to proceed when disk identification is ambiguous.
- Never assume the desktop and laptop have identical storage layouts.

### Secrets

- Never commit private keys, passwords, tokens or unencrypted secret archives.
- Never embed unencrypted credentials in an ISO.
- Never print secret contents in logs.
- Preserve restrictive file permissions when restoring credentials.
- Test secret backup and restoration using disposable test keys.
- Do not overwrite existing keys without explicit authorization.

### Host system

- Do not modify the developer's running Arch/CachyOS installation.
- Do not remove or upgrade host packages as part of project development.
- Do not modify the host's pacman configuration.
- Do not install system dependencies without permission.
- Keep build artifacts and temporary files inside designated project/build directories whenever possible.

## 3. Architecture Decisions

The following decisions are established.

### Shared components

- Archiso-based ISO generation.
- CachyOS repositories.
- CachyOS BORE LTO kernel.
- MangoWM desktop environment.
- Shared package manifests where appropriate.
- Shared dotfiles and user configuration.
- Encrypted external secret backup.
- Automated installation workflow.
- Ventoy-compatible ISO output.

### Desktop profile

- AMD microcode: `amd-ucode`.
- AMD graphics: Mesa and RADV.
- CachyOS Zen4 repository configuration.
- x86-64-v4-compatible packages.
- `linux-cachyos-bore` from the appropriate repository. All CachyOS kernels are
  LTO builds; there is no separate `-lto` package.

### Laptop profile

- Intel microcode: `intel-ucode`.
- Intel graphics: Mesa and ANV.
- CachyOS x86-64-v3 repository configuration.
- x86-64-v3-compatible packages.
- `linux-cachyos-bore` from the appropriate repository. All CachyOS kernels are
  LTO builds; there is no separate `-lto` package.

### Compatibility

- Never mix Zen4-specific packages into the laptop profile.
- Never assume packages from different CachyOS architecture repositories are interchangeable.
- Verify kernel, headers, firmware and module compatibility.
- Ensure the live ISO itself is compatible with the target processor.
- Keep desktop and laptop repository configurations independent.

If an established decision becomes technically problematic, explain why and request approval before changing it.

## 4. CachyOS and Arch Linux

Use official documentation and repository metadata.

Preferred references:

- https://wiki.archlinux.org/title/Archiso
- https://wiki.archlinux.org/title/Installation_guide
- https://wiki.archlinux.org/title/Pacman
- https://wiki.cachyos.org/
- https://github.com/CachyOS

Requirements:

- Use official CachyOS keyrings and mirror configuration.
- Verify package signatures.
- Respect repository priorities.
- Validate package architecture.
- Avoid hardcoded package versions unless necessary.
- Avoid mixing incompatible repository configurations.
- Do not assume that an installed package is available in every target repository.

If documentation or package metadata cannot be verified, report the uncertainty.

## 5. Package Management

Maintain separate manifests:

- `common/packages.txt`
- `desktop/packages.txt`
- `laptop/packages.txt`
- Corresponding AUR manifests where necessary.

Rules:

1. Avoid duplicate package declarations.
2. Avoid explicitly installing packages already pulled in as dependencies unless intentional.
3. Distinguish official repository packages from AUR packages.
4. Review foreign packages individually.
5. Do not automatically include every package from the original installation.
6. Preserve useful development tools.
7. Avoid installing hardware-specific utilities on machines that do not need them.
8. Validate manifests before building.

AUR packages must be built using a controlled, reproducible-enough workflow. Do not run AUR build processes as root.

## 6. Code Quality

Prefer:

- Bash for installation and build scripts.
- POSIX-compatible shell where practical.
- Clear function boundaries.
- Explicit error handling.
- Quoted variables.
- Meaningful exit codes.
- Idempotent configuration operations.
- Clear logging without sensitive information.

Shell scripts should generally use:

```bash
set -Eeuo pipefail
```

Use appropriate shell linting and formatting when available.

Do not hide errors with broad error suppression.

Avoid unnecessary frameworks and complex abstractions.

## 7. Installation Requirements

The final installer must:

1. Boot from Ventoy.
2. Offer desktop or laptop installation.
3. Detect hardware and available disks.
4. Require explicit disk confirmation.
5. Support UEFI.
6. Support ext4.
7. Support separate EFI and root partitions. Do not create a separate `/home`
   partition; the root partition uses all remaining disk space.
8. Install the correct CachyOS repository configuration.
9. Install the correct BORE LTO kernel.
10. Install matching microcode and graphics packages.
11. Install package manifests.
12. Restore shared dotfiles.
13. Configure systemd services.
14. Restore encrypted secrets when available.
15. Validate installation.
16. Provide a clear completion message.

Installation should fail safely when a required operation fails.

Do not claim an installation succeeded if verification failed.

## 8. Testing Requirements

Run relevant validation after every implementation task.

Depending on the changed files, this includes:

- Shell syntax checks with `bash -n`.
- ShellCheck.
- Package manifest validation.
- Repository availability checks.
- Architecture compatibility checks.
- Archiso profile validation.
- Installer dry runs.
- Secret archive integrity tests.
- ISO checksum verification.
- Virtual machine boot tests.

Never perform destructive physical installation tests.

Prefer disposable virtual machines and temporary disk images.

A successful ISO build does not automatically mean the installer works. Test both independently.

## 9. Documentation

Keep documentation synchronized with implementation.

Document:

- Repository structure.
- Build prerequisites.
- CachyOS repository differences.
- Package selection.
- ISO build commands.
- Installation workflow.
- Disk safety mechanisms.
- Secret backup and restoration.
- Testing procedures.
- Known limitations.

Do not document functionality that has not actually been implemented and tested.

## 10. Git Practices

- Use clear, descriptive commit messages.
- Keep commits focused.
- Do not commit ISO files or large build artifacts.
- Do not commit temporary build directories.
- Never commit secrets.
- Do not rewrite Git history unless explicitly requested.
- Do not push changes unless explicitly requested.

## 11. Milestone Workflow

The project follows the milestones defined in `README.md`.

For each milestone:

1. Inspect relevant files and documentation.
2. Explain the intended implementation briefly.
3. Implement only the current milestone.
4. Run relevant validation.
5. Review the changes.
6. Report completed work and unresolved issues.
7. Wait for user confirmation.

Do not continue automatically.

## 12. Completion Report Format

At the end of each milestone, report:

### Completed
- Brief list of implemented changes.

### Files changed
- List of created, modified or removed files.

### Validation
- Commands executed.
- Results.
- Tests not performed.

### Outstanding issues
- Known limitations.
- Unverified assumptions.
- Required user decisions.

### Next milestone
- State the next milestone without starting it.

Keep reports concise and factual.

---

## 13. Initial Task

For the first task:

**Complete Milestone 1: Repository Initialization only.**

- Inspect the current working directory.
- Inspect existing files before creating anything.
- Initialize the repository structure.
- Create documentation.
- Add `.gitignore`.
- Add this `AGENTS.md`.
- Document the agreed desktop and laptop architecture.

Do not:

- Install packages.
- Change host system configuration.
- Modify pacman repositories.
- Build an ISO.
- Execute disk operations.
- Generate or restore secrets.
- Begin package cleanup.

Report the completed milestone and wait for confirmation.
