#!/usr/bin/env bash
# Installer entry point. Runs from the live ISO as root.
#
# Destructive: writes a new GPT partition table and formats two partitions on
# the disk you select. Every destructive step requires typed confirmation.
#
# Usage: install.sh [--profile desktop|laptop] [--disk /dev/X] [--user NAME]
#                    [--dry-run]
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
REPO_ROOT=$(dirname -- "$SCRIPT_DIR")
readonly REPO_ROOT
readonly MOUNTPOINT=/mnt

# shellcheck source=installer/common.sh
. "$SCRIPT_DIR/common.sh"
# shellcheck source=installer/partition.sh
. "$SCRIPT_DIR/partition.sh"
# shellcheck source=installer/packages.sh
. "$SCRIPT_DIR/packages.sh"
# shellcheck source=installer/configure.sh
. "$SCRIPT_DIR/configure.sh"
# shellcheck source=installer/dotfiles.sh
. "$SCRIPT_DIR/dotfiles.sh"

PROFILE=
DISK=
TARGET_USER=enes

usage() {
	cat >&2 <<'EOF'
Usage: install.sh [--profile desktop|laptop] [--disk /dev/X] [--user NAME] [--dry-run]

  --profile    Target profile. Prompted when omitted.
  --disk       Whole disk to erase. Prompted when omitted.
  --user       Account to create and populate. Default: enes
  --dry-run    Print destructive commands instead of running them.
EOF
}

while [[ $# -gt 0 ]]; do
	case $1 in
	--profile)
		PROFILE=${2:-}
		shift 2
		;;
	--disk)
		DISK=${2:-}
		shift 2
		;;
	--user)
		TARGET_USER=${2:-}
		shift 2
		;;
	--dry-run)
		DRY_RUN=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage
		exit 64
		;;
	esac
done

select_profile() {
	if [[ -n $PROFILE ]]; then
		[[ $PROFILE == desktop || $PROFILE == laptop ]] || die "invalid profile: $PROFILE"
		return
	fi
	local answer
	printf 'Profile [desktop/laptop]: ' >&2
	read -r answer
	[[ $answer == desktop || $answer == laptop ]] || die "invalid profile: $answer"
	PROFILE=$answer
}

show_disks() {
	printf '\nAvailable disks:\n' >&2
	lsblk --paths --discard --nodeps --output NAME,SIZE,MODEL,SERIAL,TYPE >&2
	printf '\n' >&2
}

select_disk() {
	if [[ -n $DISK ]]; then
		return
	fi
	show_disks
	local answer
	printf 'Target disk (exact path, e.g. /dev/nvme0n1): ' >&2
	read -r answer
	[[ -n $answer ]] || die "no disk selected"
	DISK=$answer
}

check_network() {
	if curl --silent --fail --max-time 10 --head https://archlinux.org >/dev/null 2>&1; then
		return
	fi
	warn "network check failed; package installation will fail without connectivity"
}

main() {
	if [[ $DRY_RUN -eq 1 ]]; then
		warn "dry run: no disk will be modified"
	else
		require_root
	fi
	require_uefi
	local tool
	for tool in sgdisk mkfs.fat mkfs.ext4 pacstrap arch-chroot genfstab blkid efibootmgr; do
		if command -v "$tool" >/dev/null 2>&1; then
			continue
		fi
		if [[ $DRY_RUN -eq 1 ]]; then
			warn "missing tool for a real run: $tool"
		else
			die "missing command: $tool"
		fi
	done

	select_profile
	select_disk

	validate_whole_disk "$DISK"

	local esp root
	esp=$(partition_path "$DISK" 1)
	root=$(partition_path "$DISK" 2)

	printf '\n' >&2
	printf 'Target disk : %s\n' "$DISK" >&2
	printf 'Profile     : %s\n' "$PROFILE" >&2
	printf 'User        : %s\n' "$TARGET_USER" >&2
	printf 'ESP         : %s (FAT32, 1 GiB, mounted at /boot)\n' "$esp" >&2
	printf 'Root        : %s (ext4, rest of disk)\n' "$root" >&2
	printf '\n' >&2
	printf 'This erases the partition table and all data on %s.\n' "$DISK" >&2
	printf 'There is no undo.\n' >&2
	confirm_destructive "Destructive operation confirmed for $DISK." "$(basename "$DISK")"

	check_network

	if findmnt --mountpoint "$MOUNTPOINT" >/dev/null 2>&1; then
		die "$MOUNTPOINT is already mounted; unmount it first"
	fi

	partition_disk "$DISK"
	esp=$PARTITION_ESP
	root=$PARTITION_ROOT
	[[ -n $esp && -n $root ]] || die "partitioning did not report devices"

	run mount "$root" "$MOUNTPOINT"
	run mount --mkdir "$esp" "$MOUNTPOINT/boot"

	install_repository_packages "$MOUNTPOINT" "$PROFILE" "$REPO_ROOT"
	apply_configuration "$MOUNTPOINT" "$PROFILE" "$REPO_ROOT" "$DISK"
	create_user "$MOUNTPOINT" "$TARGET_USER"
	install_aur_packages "$MOUNTPOINT" "$PROFILE" "$REPO_ROOT" "$TARGET_USER"
	install_dotfiles "$MOUNTPOINT" "$REPO_ROOT" "$TARGET_USER"
	enable_services "$MOUNTPOINT" "$PROFILE" "$REPO_ROOT"
	build_uki "$MOUNTPOINT"
	create_boot_entry "$MOUNTPOINT" "$PROFILE" "$REPO_ROOT" "$DISK"

	printf '\nRestore an encrypted secrets archive now? Leave empty to skip.\n' >&2
	local archive
	printf 'Archive path: ' >&2
	read -r archive || true
	if [[ -n $archive ]]; then
		"$SCRIPT_DIR/restore-secrets.sh" --root "$MOUNTPOINT" --user "$TARGET_USER" "$archive"
	fi

	run umount -R "$MOUNTPOINT"

	log "installation finished for profile $PROFILE"
	log "remove the installation media and reboot"
}

main "$@"
