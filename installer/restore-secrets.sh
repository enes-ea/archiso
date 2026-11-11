#!/usr/bin/env bash
# Restore a secrets archive into a target system.
#
# Runs on the live ISO as root, or against a mounted target root. The archive is
# decrypted into a private temporary directory, validated, then merged into the
# target user's home with restrictive permissions.
#
# Usage: restore-secrets.sh --user NAME [--root DIR] [--force] ARCHIVE
#
# Environment:
#   PASSPHRASE_FILE  Read the passphrase from this file (tests only).
set -Eeuo pipefail
umask 077

readonly PROG=${0##*/}

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
info() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
	cat >&2 <<'EOF'
Usage: restore-secrets.sh --user NAME [--root DIR] [--force] ARCHIVE

  --user NAME   Target account that receives the files.
  --root DIR    Mounted target root. Default: /
  --force       Overwrite existing secret directories.
  ARCHIVE       Encrypted archive created by backup.sh.
EOF
}

TARGET_ROOT=/
TARGET_USER=
FORCE=0
ARCHIVE=

while [[ $# -gt 0 ]]; do
	case $1 in
	--user)
		TARGET_USER=${2:-}
		shift 2
		;;
	--root)
		TARGET_ROOT=${2:-}
		shift 2
		;;
	--force)
		FORCE=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	-*)
		usage
		exit 64
		;;
	*)
		ARCHIVE=$1
		shift
		;;
	esac
done

[[ -n $TARGET_USER ]] || { usage; exit 64; }
[[ -n $ARCHIVE ]] || { usage; exit 64; }
[[ -f $ARCHIVE ]] || die "archive not found: $ARCHIVE"
[[ -d $TARGET_ROOT ]] || die "target root not found: $TARGET_ROOT"

if [[ $EUID -ne 0 && ${ALLOW_UNPRIVILEGED:-0} != 1 ]]; then
	die "must run as root"
fi

passwd_file="$TARGET_ROOT/etc/passwd"
[[ -f $passwd_file ]] || die "no passwd database under $TARGET_ROOT"

entry=$(awk -F: -v user="$TARGET_USER" '$1 == user { print $3 ":" $4 ":" $6; exit }' "$passwd_file")
[[ -n $entry ]] || die "user not found in target system: $TARGET_USER"

IFS=: read -r uid gid home <<<"$entry"
[[ -n $home && $home != / ]] || die "refusing to restore into $home"
target_home="${TARGET_ROOT%/}$home"
[[ -d $target_home ]] || die "target home does not exist: $target_home"

readonly -a OUR_PATHS=(.gnupg .ssh .local/share/gopass)

for rel in "${OUR_PATHS[@]}"; do
	if [[ -e $target_home/$rel && $FORCE -ne 1 ]]; then
		die "already exists, use --force to overwrite: $target_home/$rel"
	fi
done

workdir=$(mktemp -d)
cleanup() { rm -rf -- "$workdir"; }
trap cleanup EXIT

readonly plain="$workdir/archive.tar.gz"

gpg_args=(--decrypt --no-symkey-cache --output "$plain")
if [[ -n ${PASSPHRASE_FILE:-} ]]; then
	[[ -r $PASSPHRASE_FILE ]] || die "cannot read PASSPHRASE_FILE"
	gpg_args+=(--batch --pinentry-mode loopback --passphrase-file "$PASSPHRASE_FILE")
fi

info "decrypting archive"
gpg "${gpg_args[@]}" "$ARCHIVE" || die "decryption failed"

[[ -f $plain ]] || die "decrypted archive is missing"

# Reject anything outside the expected layout before extracting.
unexpected=$(tar --list --gzip --file "$plain" | grep -vE '^(\./)?(\.gnupg|\.ssh|\.local/share/gopass)(/|$)' | head -1 || true)
[[ -z $unexpected ]] || die "archive contains unexpected path:$unexpected"

mkdir -p "$workdir/tree"
tar --extract --gzip --file "$plain" --directory "$workdir/tree" --no-same-owner

for rel in "${OUR_PATHS[@]}"; do
	[[ -e $workdir/tree/$rel ]] || continue
	rm -rf -- "${target_home:?}/$rel"
	mkdir -p -- "$(dirname -- "$target_home/$rel")"
	cp -a "$workdir/tree/$rel" "$target_home/$rel"
	chmod 700 "$target_home/$rel"
done

if [[ $EUID -eq 0 ]]; then
	chown -R "$uid:$gid" "$target_home/.gnupg" "$target_home/.ssh" 2>/dev/null || true
	chown -R "$uid:$gid" "$target_home/.local/share/gopass" 2>/dev/null || true
fi

find "$target_home/.ssh" -type f -exec chmod 600 {} + 2>/dev/null || true
find "$target_home/.ssh" -type d -exec chmod 700 {} + 2>/dev/null || true

info "restored: ${OUR_PATHS[*]} into $target_home"
info "verify ownership and permissions before rebooting"
