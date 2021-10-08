#!/bin/bash

set -e -u -o pipefail

loop_mounted=false
rootfs_mounted=false
vendor_mounted=false

usage() {
	echo "$0 usage options:"
	echo "--mount-point <dir>: Temporary directory for extracting rootfs and vendor partition"
	echo "--rootfs <file.tar.gz>: Path to input rootfs file"
	echo "--out <blk-device>|<disk-image>: Path to output block device or disk image (the type will be detected automatically)"
	echo "--label <name>: Name for the OS as will be seen in extlinux.conf"
	echo "--dtb <file>: Path to input device tree blob"
	echo "--kernel <file>: Path to input kernel file, different formats such as Image, Image.gz, uImage can be used"
	echo "[--extra-cmdline \"add here\"]: Optional extra cmdline parameters"
	echo "[--uboot-script <file.cmd>]: Optional U-Boot script to be loaded by the bootloader instead of the extlinux.conf (which is still generated)"
	echo "[--vendor-script <file.sh>]: Optional Bash script to override U-Boot flashing procedure, add extra files to vendor partition etc"
	exit
}

error() {
	local lineno="$1"
	local code="${2:-1}"

	echo "Error on line ${lineno}; status ${code}."
	exit "${code}"
}
trap 'error ${LINENO}' ERR

do_cleanup() {
	if [ ${rootfs_mounted} = true ]; then
		echo "Unmounting rootfs..."
		umount "${mnt}/rootfs"
	fi
	if [ ${vendor_mounted} = true ]; then
		echo "Unmounting vendor partition..."
		umount "${mnt}/vendor"
	fi
	if [ ${loop_mounted} = true ]; then
		echo "Unmounting loop device..."
		losetup -d "${loop}"
	fi
}
trap do_cleanup EXIT

step_flash_firmware() {
	:
}

step_append_rootfs_partition() {
	:
}

step_append_vendor_partition() {
	:
}

argc=$#
argv=( "$@" )

mnt=
out=
rootfs=
label=
dtb=
kernel=
uboot_script=
console="ttyS0,115200n8"
extra_cmdline=
vendor_script=
ptable="gpt"

i=0
while [ $i -lt $argc ]; do
	key="${argv[$i]}"
	i=$((i + 1))
	case "$key" in
	-m|--mount-point)
		mnt="${argv[$i]}"
		i=$((i + 1))
		;;
	-o|--out)
		out="${argv[$i]}"
		i=$((i + 1))
		;;
	-r|--rootfs)
		rootfs="${argv[$i]}"
		i=$((i + 1))
		;;
	-l|--label)
		label="${argv[$i]}"
		i=$((i + 1))
		;;
	-d|--dtb)
		dtb="${argv[$i]}"
		i=$((i + 1))
		;;
	-k|--kernel)
		kernel="${argv[$i]}"
		i=$((i + 1))
		;;
	-s|--uboot-script)
		uboot_script="${argv[$i]}"
		i=$((i + 1))
		;;
	-v|--vendor-script)
		vendor_script="${argv[$i]}"
		i=$((i + 1))
		;;
	*)
		echo "Unkown option \"${key}\""
		usage
		;;
	esac
done

if [ -z "${mnt}" ]; then echo "Please specify --mount-point"; exit; fi
if [ -z "${out}" ]; then echo "Please specify --out"; exit; fi
if [ -z "${rootfs}" ]; then echo "Please specify --rootfs"; exit; fi
if [ -z "${label}" ]; then echo "Please specify --label"; exit; fi
if [ -z "${dtb}" ]; then echo "Please specify --dtb"; exit; fi
if [ -z "${kernel}" ]; then echo "Please specify --kernel"; exit; fi

if [ -n "${uboot_script}" ]; then
	case "${uboot_script}" in
	*.cmd)
		;;
	*)
		echo "The U-Boot script file name must end in *.cmd"
		exit 1
		;;
	esac
fi

vendor_sector_start=2048
rootfs_sector_start=1026048

if [ -n "${vendor_script}" ]; then
	source "${vendor_script}"
fi

if [ -b "${out}" ]; then
	size_sectors=$(blockdev --getsize "${out}")
else
	rm -rf "${out}"
	fallocate -l 8G "${out}"
	size_sectors=$(($(stat --printf="%s" "${out}") / 512))
fi

vendor_sector_end=$((${rootfs_sector_start} - 1))
rootfs_sector_end=$((${size_sectors} - 50))

case ${ptable} in
mbr)
	parted -s "${out}" mktable msdos \
		mkpart primary fat32 "${vendor_sector_start}s" "${vendor_sector_end}s" \
		mkpart primary ext4 "${rootfs_sector_start}s" "${rootfs_sector_end}s"
	;;
gpt)
	sgdisk --clear --zap-all \
		--new=1:${vendor_sector_start}:${vendor_sector_end} --change-name=1:vendor --typecode=1:ef00 \
		--new=2:${rootfs_sector_start}:${rootfs_sector_end} --change-name=2:rootfs --typecode=2:8307 \
		"${out}"
	;;
*)
	echo "Unknown partition table type ${ptable}"
	exit 1
	;;
esac

if ! [ -b "${out}" ]; then
	loop=$(losetup --show -f "${out}")
	loop_mounted=true
	echo "Mounted ${out} at ${loop}"
	partprobe "${loop}"
fi

if [ -b "${out}" ]; then
	dev="${out}"
	vendor_part="${out}1"
	rootfs_part="${out}2"
else
	dev="${loop}"
	vendor_part="${loop}p1"
	rootfs_part="${loop}p2"
fi

step_build_firmware

step_flash_firmware "${dev}"

mkfs.vfat $vendor_part
mkfs.ext4 $rootfs_part

mkdir -p "${mnt}/rootfs"
mount -o rw "${rootfs_part}" "${mnt}/rootfs" && rootfs_mounted=true
# Ignore unknown extended header keywords
echo "Extracting rootfs..."
bsdtar -xpf "${rootfs}" -C "${mnt}/rootfs" || :

rootfs_partuuid=$(blkid "${rootfs_part}" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /PARTUUID/) print $i }')
case ${rootfs_partuuid} in
PARTUUID=*)
	;;
*)
	echo "Could not determine rootfs partition UUID, got ${rootfs_partuuid}, exiting."
	exit 1
	;;
esac
# Strip the quotes from the PARTUUID
rootfs_partuuid=${rootfs_partuuid//\"/}

tty=${console%,*}
if [ -f ${mnt}/rootfs/etc/securetty ]; then
	if ! grep -q ${tty} ${mnt}/rootfs/etc/securetty; then
		echo "Warning: TTY device ${tty} missing from /etc/securetty, root login might be unavailable"
	fi
fi

echo "Creating vendor partition..."
mkdir -p "${mnt}/vendor"
mount -o rw "${vendor_part}" "${mnt}/vendor" && vendor_mounted=true
mkdir -p "${mnt}/vendor/extlinux"
install -Dm0755 ${kernel} "${mnt}/vendor/"
install -Dm0755 ${dtb} "${mnt}/vendor/"
bash -c "cat > ${mnt}/vendor/extlinux/extlinux.conf" <<-EOF
label ${label}
  kernel ../$(basename ${kernel})
  devicetree ../$(basename ${dtb})
  append console=${console} root=${rootfs_partuuid} rw rootwait ${extra_cmdline}
EOF

step_append_vendor_partition "${mnt}/vendor"
step_append_rootfs_partition "${mnt}/rootfs"

if [ -n "${uboot_script}" ]; then
	uboot_script_bin="${uboot_script%.cmd}.scr"

	mkimage -C none -T script -d "${uboot_script}" "${uboot_script_bin}"
fi

sync
