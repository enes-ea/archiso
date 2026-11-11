#!/usr/bin/env bash
# shellcheck disable=SC2034
iso_name="arch-desktop"
iso_label="ARCH_DESKTOP"
iso_publisher="enes-ea <https://github.com/enes-ea/archiso>"
iso_application="Arch/CachyOS Installer - desktop"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/opt/archiso"]="0:0:755"
  ["/opt/archiso/installer"]="0:0:755"
  ["/opt/archiso/installer/install.sh"]="0:0:755"
  ["/opt/archiso/installer/restore-secrets.sh"]="0:0:755"
  ["/opt/archiso/secrets/backup.sh"]="0:0:755"
)
