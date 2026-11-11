#!/usr/bin/env bash
# User environment: dotfiles, links and Fisher plugins. Sourced by install.sh.

install_dotfiles() {
	local mountpoint=$1 repo_root=$2 user=$3

	local source="$repo_root/common/dotfiles"
	[[ -d $source ]] || die "dotfiles submodule is missing: $source"
	[[ -f $source/links.json ]] || die "dotfiles submodule is not initialized: $source"

	local home="$mountpoint/home/$user"
	if [[ $DRY_RUN -eq 0 ]]; then
		[[ -d $home ]] || die "home directory missing: $home"
	fi

	log "installing dotfiles into $home/.files"
	run install -d -o "$user" -g "$user" -m 700 "$home/.files"
	run cp -a "$source/." "$home/.files/"
	run chown -R "$user:$user" "$home/.files"

	log "applying dotfile links"
	# shellcheck disable=SC2016
	run arch-chroot "$mountpoint" runuser -u "$user" -- \
		env HOME="/home/$user" bash -c 'cd "$HOME/.files" && ./bin/dot'

	log "installing Fisher plugins"
	if [[ -f "$source/fish/fish_plugins" ]]; then
		run arch-chroot "$mountpoint" runuser -u "$user" -- \
			env HOME="/home/$user" fish -c 'fisher update'
	else
		warn "no fish/fish_plugins list, skipping Fisher"
	fi
}
