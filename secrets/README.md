# Secrets backup and restoration

Personal keys never enter Git or the ISO. They travel as one encrypted archive
on a separate USB stick, normally the Ventoy device.

## Contents

- `~/.gnupg` — GPG keys and trust database.
- `~/.ssh` — SSH keys and client configuration.
- `~/.local/share/gopass` — gopass password store.

## Create an archive

Run on the installed machine:

```bash
./secrets/backup.sh /run/media/$USER/VENTOY/secrets-alpha.tar.gz.gpg
```

- Prompts for a passphrase. It is not stored anywhere.
- Refuses to overwrite an existing file.
- Writes a `.sha256` next to the archive.
- Prints only source names, size and checksum. Never prints secrets.

## Restore during installation

Run from the live ISO, against the mounted target root:

```bash
./installer/restore-secrets.sh --root /mnt --user alpha \
  /run/media/$USER/VENTOY/secrets-alpha.tar.gz.gpg
```

- Refuses to overwrite existing directories unless `--force` is given.
- Validates that the archive holds only `.gnupg`, `.ssh` and
  `.local/share/gopass` before extracting.
- Decrypts into a private temporary directory that is removed on exit.
- Sets `.ssh` and `.gnupg` to mode 700, SSH files to mode 600, and chowns to the
  target user.

## Test round trip

```bash
./secrets/test-roundtrip.sh
```

Uses disposable fake keys, a temporary passphrase and a temporary target root.
It never reads real key material.

## Rules

- Never commit an archive, a passphrase, or a decrypted tree.
- Never print file contents during backup or restore.
- Test restoration with disposable credentials before trusting it.
- The system disk stays unencrypted. This archive is the only protection for
  the keys it carries, so the passphrase must be strong.
