#!/usr/bin/env bash
# Local PKGBUILDs stored in this repository. Sourced by install.sh.
#
# Forks and patches that are not published to the AUR live in packages/.
# Each directory needs a PKGBUILD. Builds run as the target user and installs
# run as root, so the flow never needs a sudo password.

local_packages_workdir() { printf '%s' /var/tmp/archiso-packages; }

# Print the depends and makedepends of a PKGBUILD so they can be installed as
# root before makepkg runs with --nodeps.
pkgbuild_depends() {
	local pkgbuild=$1
	(
		set +eu
		# shellcheck disable=SC1090
		source "$pkgbuild" >/dev/null 2>&1
		# shellcheck disable=SC2154 # depends/makedepends come from the PKGBUILD.
		printf '%s\n' "${depends[@]}" "${makedepends[@]}"
	) 2>/dev/null | awk 'NF && !seen[$0]++'
}

install_local_packages() {
	local mountpoint=$1 repo_root=$2 user=$3
	local source="$repo_root/packages"
	[[ -d $source ]] || return 0

	local -a dirs=()
	mapfile -t dirs < <(find "$source" -mindepth 2 -maxdepth 2 -name PKGBUILD -printf '%h\n' | sort)
	[[ ${#dirs[@]} -gt 0 ]] || return 0

	local work ids uid gid
	work=$(local_packages_workdir)
	if [[ $DRY_RUN -eq 1 ]]; then
		uid=0 gid=0
	else
		ids=$(target_ids "$mountpoint" "$user")
		IFS=: read -r uid gid <<<"$ids"
	fi
	log "building local packages from $source"
	run install -d -o "$uid" -g "$gid" -m 755 "$mountpoint$work"

	local dir name pkgbuild
	local -a deps=()
	for dir in "${dirs[@]}"; do
		name=$(basename "$dir")
		pkgbuild="$dir/PKGBUILD"
		mapfile -t deps < <(pkgbuild_depends "$pkgbuild")
		if [[ ${#deps[@]} -gt 0 ]]; then
			run arch-chroot "$mountpoint" pacman --sync --needed --noconfirm --asdeps "${deps[@]}"
		fi
		run install -d -o "$uid" -g "$gid" -m 755 "$mountpoint$work/$name"
		run cp -a "$pkgbuild" "$mountpoint$work/$name/PKGBUILD"
		log "building $name"
		run arch-chroot "$mountpoint" runuser -u "$user" -- \
			env HOME="/home/$user" \
			bash -c "cd '$work/$name' && makepkg --nodeps --noconfirm"
	done

	log "installing local packages"
	run arch-chroot "$mountpoint" bash -c "pacman -U --noconfirm $work/*/*.pkg.tar.zst"
	run rm -rf "$mountpoint$work"
}
