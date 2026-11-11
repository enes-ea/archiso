#!/usr/bin/env bash
# Runs inside the live image during the archiso build.
set -euo pipefail

systemctl enable NetworkManager.service
systemctl enable systemd-resolved.service

chmod 755 /opt/archiso/installer/*.sh

cat >/etc/motd <<'EOF'

  Arch/CachyOS installer image

  Install the system:
    /opt/archiso/installer/install.sh

  The installer asks for the profile and the target disk, then requires you to
  type the disk name before it erases anything.

EOF

ln -sfn /opt/archiso/installer/install.sh /root/install.sh
