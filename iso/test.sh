#!/usr/bin/env bash
# Boot a built ISO in QEMU with UEFI firmware and wait for the live system to
# reach multi-user mode on the serial console.
#
# Usage: test.sh desktop|laptop|all
#
# Requires qemu-system-x86_64, edk2-ovmf and libarchive (bsdtar).
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
REPO_ROOT=$(dirname -- "$SCRIPT_DIR")
readonly REPO_ROOT
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

[[ $# -eq 1 ]] || usage
target=$1
case $target in
desktop | laptop) profiles=("$target") ;;
all) profiles=(desktop laptop) ;;
*) usage ;;
esac

command -v qemu-system-x86_64 >/dev/null ||
	die "qemu-system-x86_64 not found; install qemu-full"
command -v bsdtar >/dev/null || die "bsdtar not found; install libarchive"

ovmf_code=""
for candidate in \
	/usr/share/edk2/x64/OVMF_CODE.4m.fd \
	/usr/share/edk2/ovmf/OVMF_CODE.fd \
	/usr/share/OVMF/OVMF_CODE.fd; do
	if [[ -f $candidate ]]; then
		ovmf_code=$candidate
		break
	fi
done
[[ -n $ovmf_code ]] || die "OVMF firmware not found; install edk2-ovmf"

ovmf_vars=""
for candidate in \
	/usr/share/edk2/x64/OVMF_VARS.4m.fd \
	/usr/share/edk2/ovmf/OVMF_VARS.fd \
	/usr/share/OVMF/OVMF_VARS.fd; do
	if [[ -f $candidate ]]; then
		ovmf_vars=$candidate
		break
	fi
done
[[ -n $ovmf_vars ]] || die "OVMF vars template not found; install edk2-ovmf"

workdir=$(mktemp -d)
cleanup() { rm -rf -- "$workdir"; }
trap cleanup EXIT

# Wait for a marker in a log file, then stop QEMU. Returns non-zero on timeout.
wait_for_boot() {
	local pid=$1 log_file=$2 deadline=$((SECONDS + 240))

	while ((SECONDS < deadline)); do
		if ! kill -0 "$pid" 2>/dev/null; then
			return 1
		fi
		if grep -qE 'Startup finished|Reached target Multi-User|login:' "$log_file" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			return 0
		fi
		sleep 2
	done

	kill "$pid" 2>/dev/null || true
	wait "$pid" 2>/dev/null || true
	return 1
}

failed=0
for profile in "${profiles[@]}"; do
	iso="$OUT_DIR/arch-$profile.iso"
	[[ -f $iso ]] || die "ISO not found: $iso"

	log "$profile: extracting the kernel from $iso"
	bsdtar -xf "$iso" -C "$workdir" \
		arch/boot/x86_64/vmlinuz-linux \
		arch/boot/x86_64/initramfs-linux.img ||
		die "$profile: cannot extract the kernel from the ISO"

	vars="$workdir/OVMF_VARS-$profile.fd"
	cp -- "$ovmf_vars" "$vars"
	log_file="$OUT_DIR/test-$profile.log"
	# QEMU appends to an existing serial file, so an old "reached multi-user"
	# line would match immediately. Start from an empty log.
	: >"$log_file"

	log "$profile: booting under UEFI, serial log: $log_file"
	qemu-system-x86_64 \
		-machine q35,accel=kvm:tcg \
		-m 4096 -smp 2 \
		-drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
		-drive "if=pflash,format=raw,file=$vars" \
		-cdrom "$iso" \
		-boot d \
		-display none \
		-monitor none \
		-serial "file:$log_file" \
		-no-reboot \
		-kernel "$workdir/arch/boot/x86_64/vmlinuz-linux" \
		-initrd "$workdir/arch/boot/x86_64/initramfs-linux.img" \
		-append "archisobasedir=arch archisodevice=/dev/sr0 console=ttyS0,115200 cow_spacesize=2G" \
		>/dev/null 2>&1 &
	pid=$!

	if wait_for_boot "$pid" "$log_file"; then
		log "$profile: reached multi-user"
	else
		log "$profile: failed to boot, see $log_file"
		failed=1
	fi
done

((failed == 0)) || die "one or more ISOs failed the boot test"
log "all requested ISOs booted"
