#!/usr/bin/env bash
# Round-trip test for backup.sh and restore-secrets.sh using disposable data.
# Never touches real keys.
set -Eeuo pipefail
umask 077

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly HERE
REPO=$(dirname -- "$HERE")
readonly REPO

die() { printf 'test: error: %s\n' "$*" >&2; exit 1; }
ok() { printf 'test: ok: %s\n' "$*"; }

work=$(mktemp -d)
cleanup() { rm -rf -- "$work"; }
trap cleanup EXIT

readonly source_home="$work/source"
readonly target_root="$work/target"
readonly passphrase="$work/passphrase"

mkdir -p "$source_home/.gnupg" "$source_home/.ssh" "$source_home/.local/share/gopass/stores/root"
mkdir -p "$target_root/etc" "$target_root/home/tester"

printf 'DUMMY-PRIVATE-KEY-PAYLOAD\n' >"$source_home/.ssh/id_ed25519"
chmod 600 "$source_home/.ssh/id_ed25519"
printf 'DUMMY-GPG-PAYLOAD\n' >"$source_home/.gnupg/private-keys-v1.d-test"
printf 'DUMMY-GOPASS-PAYLOAD\n' >"$source_home/.local/share/gopass/stores/root/test.gpg"
printf 'not-a-real-passphrase\n' >"$passphrase"
chmod 600 "$passphrase"
printf 'tester:x:1000:1000::/home/tester:/bin/bash\n' >"$target_root/etc/passwd"

archive="$work/secrets-test.tar.gz.gpg"

SOURCE_HOME=$source_home PASSPHRASE_FILE=$passphrase \
	"$REPO/secrets/backup.sh" "$archive" >/dev/null 2>&1 ||
	die "backup failed"
[[ -s $archive ]] || die "archive missing"
[[ $(stat -c '%a' "$archive") == 600 ]] || die "archive mode is not 600"
[[ -s $archive.sha256 ]] || die "checksum missing"
ok "archive created with mode 600 and checksum"

if grep -aq 'DUMMY-PRIVATE-KEY-PAYLOAD' "$archive"; then
	die "archive contains plaintext"
fi
ok "archive contains no plaintext"

if ALLOW_UNPRIVILEGED=1 PASSPHRASE_FILE=$passphrase \
	"$REPO/installer/restore-secrets.sh" --root "$target_root" --user tester --force "$archive" >/dev/null 2>&1; then
	ok "restore completed"
else
	die "restore failed"
fi

if ALLOW_UNPRIVILEGED=1 PASSPHRASE_FILE=$passphrase \
	"$REPO/installer/restore-secrets.sh" --root "$target_root" --user tester "$archive" >/dev/null 2>&1; then
	die "restore overwrote without --force"
fi
ok "restore refuses to overwrite"

for rel in .ssh/id_ed25519 .gnupg/private-keys-v1.d-test .local/share/gopass/stores/root/test.gpg; do
	cmp -s "$source_home/$rel" "$target_root/home/tester/$rel" || die "content mismatch: $rel"
done
ok "restored content matches"

[[ $(stat -c '%a' "$target_root/home/tester/.ssh") == 700 ]] || die ".ssh mode is not 700"
[[ $(stat -c '%a' "$target_root/home/tester/.ssh/id_ed25519") == 600 ]] || die "key mode is not 600"
ok "permissions preserved"

printf 'test: all checks passed\n'
