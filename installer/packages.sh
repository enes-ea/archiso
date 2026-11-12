#!/usr/bin/env bash
# Package installation. Sourced by install.sh.

read_manifest() {
	local file=$1
	[[ -f $file ]] || die "manifest not found: $file"
	awk '!/^[[:space:]]*#/ && NF { print $1 }' "$file"
}

# Repository packages for one profile: base plus common plus profile.
profile_packages() {
	local profile=$1 repo_root=$2
	{
		echo base
		read_manifest "$repo_root/common/packages.txt"
		read_manifest "$repo_root/$profile/packages.txt"
	} | awk '!seen[$0]++'
}

profile_aur_packages() {
	local profile=$1 repo_root=$2
	{
		read_manifest "$repo_root/common/aur-packages.txt"
		read_manifest "$repo_root/$profile/aur-packages.txt"
	} | awk '!seen[$0]++'
}

install_repository_packages() {
	local mountpoint=$1 profile=$2 repo_root=$3
	local config="$repo_root/$profile/pacman.conf"

	[[ -f $config ]] || die "pacman config not found: $config"

	log "initializing live keyring"
	if [[ ! -s /etc/pacman.d/gnupg/pubring.kbx ]]; then
		run pacman-key --init
	fi
	run pacman-key --populate archlinux cachyos

	local -a packages
	mapfile -t packages < <(profile_packages "$profile" "$repo_root")
	[[ ${#packages[@]} -gt 0 ]] || die "package list is empty"

	log "installing ${#packages[@]} repository packages"
	run pacstrap -C "$config" "$mountpoint" "${packages[@]}"

	# Keep the target in sync with the profile repositories.
	run install -Dm644 "$config" "$mountpoint/etc/pacman.conf"
}

# Copy the live mirror lists into the target. If the live system was ranked
# with cachyos-rate-mirrors, pacstrap and paru keep using the fast mirrors.
sync_live_mirrorlists() {
	local mountpoint=$1
	local list

	for list in mirrorlist cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
		[[ -f /etc/pacman.d/$list ]] || continue
		run install -Dm644 "/etc/pacman.d/$list" "$mountpoint/etc/pacman.d/$list"
	done
}

# Build and install AUR packages as the target user.
install_aur_packages() {
	local mountpoint=$1 profile=$2 repo_root=$3 user=$4
	local -a packages
	mapfile -t packages < <(profile_aur_packages "$profile" "$repo_root")
	[[ ${#packages[@]} -gt 0 ]] || {
		log "no AUR packages for $profile"
		return 0
	}

	log "installing AUR packages: ${packages[*]}"

	# paru bootstrap. It must not be built as root. paru-git is built from
	# source, so the user's rustup toolchain has to be on PATH.
	if ! arch-chroot "$mountpoint" pacman -Q paru-git >/dev/null 2>&1; then
		run arch-chroot "$mountpoint" runuser -u "$user" -- \
			git clone https://aur.archlinux.org/paru-git.git "/home/$user/paru-git"
		run arch-chroot "$mountpoint" runuser -u "$user" -- \
			env "HOME=/home/$user" \
			"PATH=/home/$user/.local/share/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
			bash -c "cd /home/$user/paru-git && makepkg --syncdeps --install --noconfirm"
		run arch-chroot "$mountpoint" rm -rf "/home/$user/paru-git"
	fi

	local -a remaining=()
	local pkg
	for pkg in "${packages[@]}"; do
		[[ $pkg == paru-git ]] && continue
		remaining+=("$pkg")
	done
	[[ ${#remaining[@]} -gt 0 ]] || return 0

	run arch-chroot "$mountpoint" runuser -u "$user" -- \
		paru --sync --needed --noconfirm "${remaining[@]}"
}
