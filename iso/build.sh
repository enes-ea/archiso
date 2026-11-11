#!/usr/bin/env bash
# Build one or both installation ISOs with archiso.
#
# Usage: build.sh desktop|laptop|all
#
# Requires root, mkarchiso, rsync, and a populated pacman keyring.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
REPO_ROOT=$(dirname -- "$SCRIPT_DIR")
readonly REPO_ROOT
readonly WORK_DIR="$SCRIPT_DIR/work"
readonly OUT_DIR="$REPO_ROOT/output"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() {
	printf '[error] %s\n' "$*" >&2
	exit 1
}

usage() {
	printf 'Usage: %s desktop|laptop|all\n' "${0##*/}" >&2
	exit 64
}

build_profile() {
	local profile=$1
	local stage="$WORK_DIR/stage-$profile"
	local work="$WORK_DIR/$profile"

	log "staging profile $profile"
	rm -rf -- "$stage" "$work"
	install -d -- "$stage" "$work" "$OUT_DIR"

	cp -a "$SCRIPT_DIR/common/." "$stage/"
	cp -a "$SCRIPT_DIR/$profile/." "$stage/"

	install -d -- "$stage/airootfs/opt/archiso"
	rsync -a \
		--exclude '.git' \
		--exclude 'output' \
		--exclude 'iso' \
		--exclude 'common/dotfiles/.git' \
		"$REPO_ROOT/" "$stage/airootfs/opt/archiso/"

	log "preparing live keyring"
	pacman-key --gpgdir "$stage/airootfs/etc/pacman.d/gnupg" --init
	pacman-key --gpgdir "$stage/airootfs/etc/pacman.d/gnupg" --populate archlinux cachyos

	log "building $profile ISO"
	mkarchiso -v -w "$work" -o "$OUT_DIR" "$stage"

	local iso_name
	iso_name=$(awk -F'"' '/^iso_name=/ { print $2 }' "$stage/profiledef.sh")

	# mkarchiso appends the ISO version and architecture to the name.
	local built
	built=$(compgen -G "$OUT_DIR/$iso_name-*.iso" | sort | tail -1 || true)
	[[ -n $built ]] || die "no ISO matching $OUT_DIR/$iso_name-*.iso"

	local iso="$OUT_DIR/$iso_name.iso"
	mv -f -- "$built" "$iso"

	log "writing checksum"
	(cd -- "$OUT_DIR" && sha256sum "${iso##*/}" >"${iso##*/}.sha256")

	log "done: $iso"
}

[[ $# -eq 1 ]] || usage
[[ $EUID -eq 0 ]] || die "mkarchiso must run as root"
command -v mkarchiso >/dev/null 2>&1 || die "mkarchiso not found: install the archiso package"
command -v rsync >/dev/null 2>&1 || die "rsync not found"

case $1 in
desktop | laptop) build_profile "$1" ;;
all)
	build_profile desktop
	build_profile laptop
	;;
*) usage ;;
esac
