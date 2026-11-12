#!/usr/bin/env bash
# Merge upstream changes into the mango and mangobar forks, then rewrite the
# PKGBUILD pins in this repo.
#
# Usage: update-forks.sh [--push]
#
# The fork checkouts default to $HOME/Projects/mangobar/{mango,mangobar}.
# Override them with MANGO_SRC and MANGOBAR_SRC.
#
# This script never commits the PKGBUILD change for you. Review the diff, then
# commit it with the archiso repo as usual.
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
REPO_ROOT=$(dirname -- "$SCRIPT_DIR")
readonly REPO_ROOT

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[warn] %s\n' "$*" >&2; }
die() {
	printf '[error] %s\n' "$*" >&2
	exit 1
}

usage() {
	printf 'Usage: %s [--push]\n' "${0##*/}" >&2
	exit 64
}

push=0
while (($#)); do
	case $1 in
	--push) push=1 ;;
	-h | --help) usage ;;
	*) usage ;;
	esac
	shift
done

command -v git >/dev/null || die "git is required"

# name, checkout, branch, pkgbuild directory
readonly -a NAMES=(mango mangobar)
readonly -a SOURCES=(
	"${MANGO_SRC:-$HOME/Projects/mangobar/mango}"
	"${MANGOBAR_SRC:-$HOME/Projects/mangobar/mangobar}"
)
readonly -a BRANCHES=(main main)
readonly -a PKGDIRS=(packages/mangowm-git packages/mangobar-git)

# Refuse to start unless every checkout is present and clean. A merge in one
# fork must not happen while another fork still has work in progress.
for i in "${!NAMES[@]}"; do
	name=${NAMES[$i]}
	src=${SOURCES[$i]}
	branch=${BRANCHES[$i]}
	[[ -d $src/.git ]] || die "$name: fork checkout not found: $src"
	[[ -z $(git -C "$src" status --porcelain) ]] ||
		die "$name: uncommitted changes in $src; commit or stash them first"
	git -C "$src" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null ||
		die "$name: branch not found: $branch"
	[[ -f $REPO_ROOT/${PKGDIRS[$i]}/PKGBUILD ]] ||
		die "$name: PKGBUILD not found: $REPO_ROOT/${PKGDIRS[$i]}/PKGBUILD"
done

# Merge phase: every fork first, so a conflict stops before any pin changes.
for i in "${!NAMES[@]}"; do
	name=${NAMES[$i]}
	src=${SOURCES[$i]}
	branch=${BRANCHES[$i]}

	log "$name: $src"
	git -C "$src" fetch --quiet upstream ||
		die "$name: cannot fetch upstream"

	current=$(git -C "$src" rev-parse --abbrev-ref HEAD)
	if [[ $current != "$branch" ]]; then
		log "$name: switching from $current to $branch"
		git -C "$src" checkout --quiet "$branch" ||
			die "$name: cannot check out $branch"
	fi

	behind=$(git -C "$src" rev-list --count HEAD..upstream/main)
	if ((behind > 0)); then
		log "$name: merging $behind commit(s) from upstream/main"
		if ! git -C "$src" merge --no-edit upstream/main; then
			die "$name: merge conflict, resolve it in $src and rerun"
		fi
	else
		log "$name: already up to date with upstream/main"
	fi
done

# Pin phase: only reached when every merge succeeded.
for i in "${!NAMES[@]}"; do
	name=${NAMES[$i]}
	src=${SOURCES[$i]}
	branch=${BRANCHES[$i]}
	pkgbuild="$REPO_ROOT/${PKGDIRS[$i]}/PKGBUILD"

	sha=$(git -C "$src" rev-parse HEAD)
	short=$(git -C "$src" rev-parse --short HEAD)
	count=$(git -C "$src" rev-list --count HEAD)

	log "$name: pin r${count}.${short} (${sha:0:12})"
	sed -i -E "s/^pkgver=.*/pkgver=r${count}.${short}/" "$pkgbuild"
	sed -i -E "s/#commit=[0-9a-f]{40}/#commit=${sha}/" "$pkgbuild"
	grep -q "#commit=${sha}" "$pkgbuild" ||
		die "$name: could not pin the commit in $pkgbuild"
	grep -qx "pkgver=r${count}\.${short}" "$pkgbuild" ||
		die "$name: could not set pkgver in $pkgbuild"

	if ((push)); then
		log "$name: pushing $branch to origin"
		git -C "$src" push origin "$branch" || die "$name: push failed"
	else
		warn "$name: not pushed, run: git -C $src push origin $branch"
	fi
done

log "PKGBUILD diff"
git -C "$REPO_ROOT" --no-pager diff --stat -- packages || true

log "rebuild and install"
printf '  (cd %s/packages/mangowm-git && makepkg --nodeps -f)\n' "$REPO_ROOT" >&2
printf '  (cd %s/packages/mangobar-git && makepkg --nodeps -f)\n' "$REPO_ROOT" >&2
