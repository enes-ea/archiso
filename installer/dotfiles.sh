#!/usr/bin/env bash
# User environment: dotfiles, links and Fisher plugins. Sourced by install.sh.

# Turn the copied dotfiles into a real repository with the public remote, so
# the installed machine can run "git pull" instead of rebuilding the ISO.
# Without network access the tree becomes a snapshot commit on the same remote.
attach_dotfiles_git() {
	local mountpoint=$1 user=$2
	local url="https://github.com/enes-ea/.files.git"
	local pin=""
	local rev_file="$3"

	[[ -f $rev_file ]] && pin=$(<"$rev_file")

	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] git init %s/home/%s/.files and fetch %s%s\n' \
			"$mountpoint" "$user" "$url" "${pin:+ at $pin}"
		return 0
	fi

	# The submodule checkout leaves a gitfile that points outside the target.
	run rm -f "$mountpoint/home/$user/.files/.git"

	# shellcheck disable=SC2016
	run arch-chroot "$mountpoint" runuser -u "$user" -- \
		env HOME="/home/$user" bash -c '
			set -e
			cd "$HOME/.files"
			git init --quiet --initial-branch=main
			git remote add origin "$1"

			# Prefer the exact commit the ISO shipped, so the target matches
			# what was tested. Fall back to main, then to a local snapshot.
			fetched=0
			if [[ -n $2 ]] && git fetch --quiet --depth 1 origin "$2"; then
				git reset --quiet --hard "$2"
				git update-ref refs/remotes/origin/main "$2"
				fetched=1
			elif git fetch --quiet --depth 1 origin main:refs/remotes/origin/main; then
				git reset --quiet --hard refs/remotes/origin/main
				fetched=1
			fi

			if ((fetched)); then
				git branch --quiet --set-upstream-to=origin/main main
				exit 0
			fi

			echo "[warn] cannot reach the dotfiles remote; leaving a snapshot" >&2
			git add --all
			git -c user.name=dotfiles -c user.email=dotfiles@localhost \
				commit --quiet --message "snapshot from the installer"
			echo "[warn] later: git fetch origin main && git reset --hard origin/main" >&2
		' bash "$url" "$pin"
}

install_dotfiles() {
	local mountpoint=$1 repo_root=$2 user=$3

	local source="$repo_root/common/dotfiles"
	[[ -d $source ]] || die "dotfiles submodule is missing: $source"
	[[ -f $source/links.json ]] || die "dotfiles submodule is not initialized: $source"

	local home="$mountpoint/home/$user"
	local uid=0 gid=0 entry

	if [[ $DRY_RUN -eq 0 ]]; then
		[[ -d $home ]] || die "home directory missing: $home"
		entry=$(awk -F: -v user="$user" '$1 == user { print $3 ":" $4; exit }' \
			"$mountpoint/etc/passwd")
		[[ -n $entry ]] || die "user not found in target system: $user"
		IFS=: read -r uid gid <<<"$entry"
	fi

	log "installing dotfiles into $home/.files"
	run install -d -m 700 "$home/.files"
	run cp -a "$source/." "$home/.files/"
	run chown -R "$uid:$gid" "$home/.files"
	run chmod 755 "$home/.files/bin/"*

	attach_dotfiles_git "$mountpoint" "$user" "$repo_root/.dotfiles-rev"

	log "applying dotfile links"
	# shellcheck disable=SC2016
	run arch-chroot "$mountpoint" runuser -u "$user" -- \
		env HOME="/home/$user" bash -c 'cd "$HOME/.files" && ./bin/dot'

	# Fisher plugins are vendored in the dotfiles (functions, conf.d,
	# completions, themes), so there is nothing to install here. Update them
	# by pulling .files instead of running "fisher update" over the tree.
}
