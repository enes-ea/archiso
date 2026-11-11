#!/usr/bin/env bash
# Whole-disk GPT partitioning and formatting. Sourced by install.sh.

# Refuse anything that is not a whole block device.
validate_whole_disk() {
	local disk=$1

	[[ -n $disk ]] || die "no disk given"
	[[ $disk == /dev/* ]] || die "disk must be a /dev path: $disk"
	if [[ $DRY_RUN -eq 0 ]]; then
		[[ -b $disk ]] || die "not a block device: $disk"
	fi
	[[ $(lsblk -dno TYPE "$disk") == disk ]] || die "not a whole disk: $disk"
	[[ $(lsblk -dno RO "$disk") == 0 ]] || die "disk is read-only: $disk"

	[[ $DRY_RUN -eq 1 ]] && return 0

	local mounted
	mounted=$(lsblk -rno MOUNTPOINT "$disk" | grep -v '^$' || true)
	[[ -z $mounted ]] || die "disk or a partition is mounted: $mounted"

	local holders
	holders=$(lsblk -rno NAME,TYPE "$disk" | awk '$2 == "disk" || $2 == "part" { print $1 }' | while read -r name; do
		[[ -d /sys/block/"$name"/holders ]] || continue
		find /sys/block/"$name"/holders -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null || true
	done)
	[[ -z $holders ]] || die "disk has active device-mapper holders: $(echo "$holders" | tr '\n' ' ')"

	# Never touch the disk that hosts the running system.
	local root_source
	root_source=$(findmnt -no SOURCE / 2>/dev/null || true)
	if [[ -n $root_source && $root_source == "$disk"* ]]; then
		die "refusing to erase the disk that hosts the running system: $disk"
	fi
}

partition_disk() {
	local disk=$1

	validate_whole_disk "$disk"

	local esp root
	esp=$(partition_path "$disk" 1)
	root=$(partition_path "$disk" 2)

	log "partitioning $disk"
	run wipefs --all --force "$disk"
	run sgdisk --zap-all "$disk"
	run sgdisk --new=1:0:+1GiB --typecode=1:ef00 --change-name=1:EFI "$disk"
	run sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:ROOT "$disk"
	run partprobe "$disk"
	run udevadm settle

	log "formatting $esp as FAT32"
	run mkfs.fat -F32 -n EFI "$esp"

	log "formatting $root as ext4"
	run mkfs.ext4 -F -L ROOT -m 1 "$root"

	# shellcheck disable=SC2034 # consumed by install.sh
	PARTITION_ESP=$esp
	# shellcheck disable=SC2034 # consumed by install.sh
	PARTITION_ROOT=$root
}
