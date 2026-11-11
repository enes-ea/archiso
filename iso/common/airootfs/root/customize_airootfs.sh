#!/usr/bin/env bash
# Runs inside the live image during the archiso build.
set -euo pipefail

systemctl enable NetworkManager.service
systemctl enable systemd-resolved.service
systemctl enable sshd.service
systemctl mask systemd-firstboot.service

# Live-only root access for remote installer use. The target stays different.
printf 'root:root\n' | chpasswd
install -d /etc/ssh/sshd_config.d
printf 'PermitRootLogin yes\nPasswordAuthentication yes\n' \
	>/etc/ssh/sshd_config.d/10-root-login.conf

# GPG in the live console needs a TTY pinentry and a known terminal.
install -d -m 700 /root/.gnupg
printf 'pinentry-program /usr/bin/pinentry-tty\n' >/root/.gnupg/gpg-agent.conf
cat >/etc/profile.d/gpg-tty.sh <<'EOF'
if [ -t 0 ]; then export GPG_TTY=$(tty); fi
EOF

# pacstrap uses the live mirrorlist, so keep Arch mirrors active here.
cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = https://archlinux.cachyos.org/repo/$repo/os/$arch
Server = https://mirror.alastyr.com/archlinux/$repo/os/$arch
Server = https://mirror.verinomi.com/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF

# Avoid systemd-firstboot prompting before the installer starts.
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime
printf 'LANG=en_US.UTF-8\n' >/etc/locale.conf
printf 'KEYMAP=us\n' >/etc/vconsole.conf

chmod 755 /opt/archiso/installer/*.sh

cat >/etc/motd <<'EOF'

  Arch/CachyOS installer image

  Install the system:
    /opt/archiso/installer/install.sh

  The installer asks for the profile and the target disk, then requires you to
  type the disk name before it erases anything.

  SSH is enabled for root with password root/root. Use it only on a trusted
  network and disconnect when the installation is done.

  Fish is installed but is not the login shell. Start it with: fish

  Speed up the install by ranking mirrors first: cachyos-rate-mirrors

EOF

ln -sfn /opt/archiso/installer/install.sh /root/install.sh
