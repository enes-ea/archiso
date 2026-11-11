#!/usr/bin/env bash
# Target system configuration inside the mounted root. Sourced by install.sh.

kernel_name() {
	local profile=$1 repo_root=$2
	local preset
	preset=$(find "$repo_root/$profile/profile/etc/mkinitcpio.d" -name '*.preset' -printf '%f\n' | head -1)
	[[ -n $preset ]] || die "no mkinitcpio preset for profile $profile"
	printf '%s' "${preset%.preset}"
}

copy_tree() {
	local source=$1 destination=$2
	[[ -d $source ]] || return 0
	run cp -a "$source/." "$destination/"
}

apply_configuration() {
	local mountpoint=$1 profile=$2 repo_root=$3 disk=$4

	log "copying shared system configuration"
	copy_tree "$repo_root/common/system/etc" "$mountpoint/etc"
	copy_tree "$repo_root/$profile/profile/etc" "$mountpoint/etc"
	copy_tree "$repo_root/$profile/system/etc" "$mountpoint/etc"

	local root_uuid
	if [[ $DRY_RUN -eq 1 ]]; then
		root_uuid=dry-run-uuid
	else
		root_uuid=$(blkid -s UUID -o value "$(partition_path "$disk" 2)") || true
		[[ -n ${root_uuid:-} ]] || die "cannot read root partition UUID"
	fi

	log "writing kernel command line"
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] sed -i s/@ROOT_UUID@/%s/ %s/etc/kernel/cmdline\n' "$root_uuid" "$mountpoint"
	else
		sed -i "s/@ROOT_UUID@/$root_uuid/" "$mountpoint/etc/kernel/cmdline"
	fi

	log "generating locale"
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] enable en_US.UTF-8 in %s/etc/locale.gen\n' "$mountpoint"
	else
		sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "$mountpoint/etc/locale.gen"
	fi
	run arch-chroot "$mountpoint" locale-gen

	log "setting hardware clock"
	run arch-chroot "$mountpoint" hwclock --systohc

	log "generating fstab"
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] genfstab -U %s >> %s/etc/fstab\n' "$mountpoint" "$mountpoint"
	else
		genfstab -U "$mountpoint" >>"$mountpoint/etc/fstab"
	fi
}

create_user() {
	local mountpoint=$1 user=$2 groups=$3 shell=$4
	local password=${INSTALL_PASSWORD:-$user}

	if [[ $user == root ]]; then
		log "configuring root account"
	else
		log "creating user $user"
		run arch-chroot "$mountpoint" useradd --create-home \
			--groups "$groups" --shell "$shell" "$user"
	fi

	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] set default password for %s and expire it\n' "$user"
	else
		printf '%s:%s\n' "$user" "$password" | arch-chroot "$mountpoint" chpasswd
		run arch-chroot "$mountpoint" chage -d 0 "$user"
	fi
}

create_users() {
	local mountpoint=$1 repo_root=$2
	local manifest="$repo_root/common/users.txt"
	[[ -f $manifest ]] || die "user manifest not found: $manifest"

	local user groups shell
	while IFS=: read -r user groups shell; do
		[[ -n $user ]] || continue
		create_user "$mountpoint" "$user" "${groups:-wheel}" "${shell:-/usr/bin/fish}"
	done < <(awk '!/^[[:space:]]*#/ && NF' "$manifest")

	log "allowing wheel group sudo"
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] enable wheel sudo in %s/etc/sudoers\n' "$mountpoint"
	else
		sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$mountpoint/etc/sudoers"
	fi
	run arch-chroot "$mountpoint" visudo --check
}

enable_services() {
	local mountpoint=$1 profile=$2 repo_root=$3

	local -a units=()
	mapfile -t units < <(
		{
			read_manifest "$repo_root/common/system/services.txt"
			read_manifest "$repo_root/$profile/profile/services.txt"
		} | awk '!seen[$0]++'
	)

	local unit
	for unit in "${units[@]}"; do
		if [[ $DRY_RUN -eq 1 ]] || arch-chroot "$mountpoint" systemctl list-unit-files "$unit" >/dev/null 2>&1; then
			run arch-chroot "$mountpoint" systemctl enable "$unit"
		else
			warn "unit not installed, skipping: $unit"
		fi
	done
}

build_uki() {
	local mountpoint=$1

	log "building unified kernel image"
	run arch-chroot "$mountpoint" mkinitcpio --allpresets
}

create_boot_entry() {
	local mountpoint=$1 profile=$2 repo_root=$3 disk=$4
	local preset uki_path loader

	preset=$(find "$repo_root/$profile/profile/etc/mkinitcpio.d" -name '*.preset' | head -1)
	[[ -n $preset ]] || die "no mkinitcpio preset for profile $profile"

	uki_path=$(awk -F'"' '/^default_uki=/ { print $2; exit }' "$preset")
	[[ -n $uki_path ]] || die "no default_uki in $preset"

	if [[ $DRY_RUN -eq 0 && ! -f "$mountpoint$uki_path" ]]; then
		die "unified kernel image not found: $uki_path"
	fi

	loader="\\"
	loader+=$(printf '%s' "${uki_path#/boot/}" | sed 's|/|\\|g')

	log "creating UEFI boot entry"
	run efibootmgr --create --disk "$disk" --part 1 --label 'Arch Linux' --loader "$loader"
}
