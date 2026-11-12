#!/usr/bin/env bash
# Shared helpers for the installer. Sourced, never executed directly.

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[warn] %s\n' "$*" >&2; }
die() {
	printf '[error] %s\n' "$*" >&2
	exit 1
}

require_root() { [[ $EUID -eq 0 ]] || die "run as root"; }
require_uefi() { [[ -d /sys/firmware/efi ]] || die "system is not booted in UEFI mode"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# DRY_RUN=1 prints commands instead of running them. Destructive steps must
# honour this so the flow can be reviewed without touching a disk.
DRY_RUN=${DRY_RUN:-0}

run() {
	if [[ $DRY_RUN -eq 1 ]]; then
		printf '[dry-run] %q ' "$@"
		printf '\n'
		return 0
	fi
	"$@"
}

# Confirm a destructive action. Requires an exact word, never a bare newline.
confirm_destructive() {
	local prompt=$1 expected=$2 answer
	printf '%s\n' "$prompt" >&2
	printf 'Type %s to continue: ' "$expected" >&2
	read -r answer
	[[ $answer == "$expected" ]] || die "aborted by user"
}

# Return "uid:gid" for a user that exists in a mounted target root, not on the
# live system. Every chown against the target must use numeric IDs.
target_ids() {
	local mountpoint=$1 user=$2 entry

	entry=$(awk -F: -v u="$user" '$1 == u { print $3 ":" $4 }' "$mountpoint/etc/passwd")
	[[ -n $entry ]] || die "cannot resolve uid/gid for $user in $mountpoint/etc/passwd"
	printf '%s' "$entry"
}

# Return the partition path for a whole disk and an index.
partition_path() {
	local disk=$1 index=$2
	if [[ $disk =~ [0-9]$ ]]; then
		printf '%sp%s' "$disk" "$index"
	else
		printf '%s%s' "$disk" "$index"
	fi
}
