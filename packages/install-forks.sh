#!/usr/bin/env bash
# Build and install the local mango fork packages on this machine.
#
# Usage: install-forks.sh [--yes]
#
# Replacing a running compositor ends the session. Run this from a tty, or pass
# --yes when you accept losing the current Mango session.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() {
	printf '[error] %s\n' "$*" >&2
	exit 1
}

usage() {
	printf 'Usage: %s [--yes]\n' "${0##*/}" >&2
	exit 64
}

yes=0
while (($#)); do
	case $1 in
	--yes) yes=1 ;;
	-h | --help) usage ;;
	*) usage ;;
	esac
	shift
done

((EUID != 0)) || die "run as your user, not root; makepkg refuses to build as root"
command -v makepkg >/dev/null || die "makepkg is required"
command -v pacman >/dev/null || die "pacman is required"

readonly -a PKGDIRS=(mangowm-git mangobar-git)

if pgrep -x mango >/dev/null; then
	if ((!yes)); then
		log "a Mango session is running; installing replaces the compositor"
		if [[ -t 0 ]]; then
			printf 'The current session will end. Continue? [y/N] ' >&2
			read -r reply
			[[ $reply == [yY]* ]] || die "aborted; rerun from a tty or pass --yes"
		else
			die "a Mango session is running; rerun from a tty or pass --yes"
		fi
	fi
fi

built=()
for dir in "${PKGDIRS[@]}"; do
	path="$SCRIPT_DIR/$dir"
	[[ -f $path/PKGBUILD ]] || die "PKGBUILD not found: $path/PKGBUILD"
	log "building $dir"
	(cd "$path" && makepkg --nodeps --noconfirm --force) ||
		die "build failed: $dir"

	mapfile -t -O "${#built[@]}" built < <(cd "$path" && makepkg --packagelist)
done

[[ ${#built[@]} -gt 0 ]] || die "no package files were built"

log "installing ${#built[@]} package file(s)"
sudo pacman -U --noconfirm "${built[@]}" || die "pacman -U failed"

log "installed versions"
pacman -Q mangowm-enes-git mangobar-enes-git
