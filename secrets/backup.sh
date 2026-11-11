#!/usr/bin/env bash
# Create an encrypted archive of personal secrets.
#
# The archive is written to an explicit output path, normally on the Ventoy
# USB. Nothing is printed except source directory names and the archive path.
#
# Usage: backup.sh OUTPUT
#
# Environment:
#   SOURCE_HOME      Home directory to read from. Default: $HOME.
#   PASSPHRASE_FILE  Read the passphrase from this file (tests only).
set -Eeuo pipefail
umask 077

if [[ -z ${GPG_TTY:-} && -t 0 ]]; then
	GPG_TTY=$(tty)
	export GPG_TTY
fi

readonly PROG=${0##*/}

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }
info() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
	cat >&2 <<'EOF'
Usage: backup.sh OUTPUT

Writes an AES256-encrypted archive to OUTPUT. The passphrase is read from the
terminal, or from PASSPHRASE_FILE when set.
EOF
}

[[ $# -eq 1 ]] || { usage; exit 64; }
readonly OUTPUT=$1
[[ $OUTPUT != -* ]] || { usage; exit 64; }
[[ -n $OUTPUT ]] || { usage; exit 64; }
[[ ! -e $OUTPUT ]] || die "refusing to overwrite existing file: $OUTPUT"

readonly SOURCE_HOME=${SOURCE_HOME:-$HOME}
[[ -d $SOURCE_HOME ]] || die "source home is not a directory: $SOURCE_HOME"

readonly -a RELATIVE_PATHS=(.gnupg .ssh .local/share/gopass)
present=()
for rel in "${RELATIVE_PATHS[@]}"; do
	[[ -e "$SOURCE_HOME/$rel" ]] && present+=("$rel")
done
[[ ${#present[@]} -gt 0 ]] || die "nothing to back up under $SOURCE_HOME"

gpg_args=(
	--symmetric
	--cipher-algo AES256
	--s2k-digest-algo SHA512
	--s2k-count 65011712
	--no-symkey-cache
	--output "$OUTPUT"
)
if [[ -n ${PASSPHRASE_FILE:-} ]]; then
	[[ -r $PASSPHRASE_FILE ]] || die "cannot read PASSPHRASE_FILE"
	gpg_args+=(--batch --pinentry-mode loopback --passphrase-file "$PASSPHRASE_FILE")
fi

info "sources: ${present[*]}"
info "output: $OUTPUT"

tar \
	--create \
	--gzip \
	--file - \
	--directory "$SOURCE_HOME" \
	--exclude 'S.*' \
	--exclude '*.lock' \
	--exclude '.#*' \
	--exclude '*.tmp' \
	"${present[@]}" | gpg "${gpg_args[@]}"

[[ -s $OUTPUT ]] || die "archive was not created"
chmod 600 "$OUTPUT"

sha256sum "$OUTPUT" >"$OUTPUT.sha256"
chmod 600 "$OUTPUT.sha256"

info "archive: $(stat -c '%s bytes' "$OUTPUT")"
info "checksum: $(cut -d' ' -f1 "$OUTPUT.sha256")"
