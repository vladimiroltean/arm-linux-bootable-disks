#!/bin/bash

set -e -u -o pipefail

loop_mounted=false
rootfs_mounted=false
vendor_mounted=false

usage() {
	echo "$0 usage options:"
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
		sudo umount "${mnt}/rootfs"
	fi
	if [ ${vendor_mounted} = true ]; then
		echo "Unmounting vendor partition..."
		sudo umount "${mnt}/vendor"
	fi
	if [ ${loop_mounted} = true ]; then
		echo "Unmounting loop device..."
		sudo losetup -d "${loop}"
	fi
}
trap do_cleanup EXIT

get_partuuid() {
	local partition="${1}"
	local partuuid=

	partuuid=$(blkid "${partition}" | awk '{ for(i=1;i<=NF;i++) if ($i ~ /PARTUUID/) print $i }')
	case ${partuuid} in
	PARTUUID=*)
		;;
	*)
		echo "Could not determine partition UUID, got ${partuuid}, exiting."
		exit 1
		;;
	esac
	# Strip the quotes from the PARTUUID
	partuuid=${partuuid//\"/}
	echo "${partuuid}"
}

full_steps=(
	step_prepare_partition_table
	step_mount_loop_device
	step_build_firmware
	step_prepare_uboot_script
	step_flash_firmware
	step_prepare_rootfs_partition
	step_prepare_vendor_partition
	step_append_vendor_partition
	step_append_rootfs_partition
	step_prepare_fstab
)

run_step() {
	local step="${1}"

	if [[ " ${steps[*]} " =~ " ${step} " ]]; then
		$@
	fi
}

# Do not expect vendor scripts to override this
step_prepare_partition_table() {
	if [ -b "${out}" ]; then
		size_sectors=$(sudo blockdev --getsize "${out}")
	else
		rm -rf "${out}"
		fallocate -l 8G "${out}"
		size_sectors=$(($(stat --printf="%s" "${out}") / 512))
	fi

	vendor_sector_end=$((${rootfs_sector_start} - 1))
	rootfs_sector_end=$((${size_sectors} - 50))

	case ${ptable} in
	mbr)
		sudo parted -s "${out}" mktable msdos \
			mkpart primary fat32 "${vendor_sector_start}s" "${vendor_sector_end}s" \
			mkpart primary ext4 "${rootfs_sector_start}s" "${rootfs_sector_end}s"
		;;
	gpt)
		sudo sgdisk --clear --zap-all \
			--new=1:${vendor_sector_start}:${vendor_sector_end} --change-name=1:vendor --typecode=1:ef00 \
			--new=2:${rootfs_sector_start}:${rootfs_sector_end} --change-name=2:rootfs --typecode=2:8307 \
			"${out}"
		;;
	*)
		echo "Unknown partition table type ${ptable}"
		exit 1
		;;
	esac
}

# Do not expect vendor scripts to override this
step_mount_loop_device() {
	if ! [ -b "${out}" ]; then
		loop=$(sudo losetup --show -f "${out}")
		loop_mounted=true
		echo "Mounted ${out} at ${loop}"
		sudo partprobe "${loop}"
	fi
}

step_flash_firmware() {
	:
}

# Do not expect vendor scripts to override this
step_prepare_uboot_script() {
	if [ -n "${uboot_script}" ]; then
		uboot_script_bin="${uboot_script%.cmd}.scr"

		mkimage -C none -T script -d "${uboot_script}" "${uboot_script_bin}"
	fi
}

# Do not expect vendor scripts to override this
step_prepare_rootfs_partition() {
	local rootfs_part="${1}"
	local rootfs_mnt="${2}"

	sudo mkfs.ext4 $rootfs_part

	mkdir -p "${rootfs_mnt}"
	sudo mount -o rw "${rootfs_part}" "${rootfs_mnt}" && rootfs_mounted=true
	# Ignore unknown extended header keywords
	echo "Extracting rootfs..."
	sudo bsdtar -xpf "${rootfs}" -C "${rootfs_mnt}" || :

	rootfs_partuuid=$(get_partuuid ${rootfs_part})

	tty=${console%,*}
	if [ -f "${rootfs_mnt}/etc/securetty" ]; then
		if ! grep -q ${tty} "${rootfs_mnt}/etc/securetty"; then
			echo "Warning: TTY device ${tty} missing from /etc/securetty, root login might be unavailable"
		fi
	fi
}

# Do not expect vendor scripts to override this
step_prepare_vendor_partition() {
	local vendor_part="${1}"
	local vendor_mnt="${2}"

	sudo mkfs.vfat $vendor_part

	vendor_partuuid=$(get_partuuid ${vendor_part})

	echo "Creating vendor partition..."
	sudo mkdir -p "${vendor_mnt}"
	sudo mount -o rw "${vendor_part}" "${vendor_mnt}" && vendor_mounted=true
	sudo mkdir -p "${vendor_mnt}/extlinux"
	sudo install -Dm0755 ${kernel} "${vendor_mnt}/"
	sudo install -Dm0755 ${dtb} "${vendor_mnt}/"
	if [ -n "${uboot_script_bin}" ]; then
		sudo install -Dm0755 "${uboot_script_bin}" "${vendor_mnt}"
	fi
	sudo bash -c "cat > ${vendor_mnt}/extlinux/extlinux.conf" <<-EOF
	label ${label}
	  kernel ../$(basename ${kernel})
	  devicetree ../$(basename ${dtb})
	  append console=${console} root=${rootfs_partuuid} rw rootwait ${extra_cmdline}
	EOF
}

step_append_rootfs_partition() {
	:
}

step_append_vendor_partition() {
	:
}

step_prepare_fstab() {
	local rootfs_mnt="${1}"

	sudo bash -c "cat > ${rootfs_mnt}/etc/fstab" <<-EOF
PARTUUID="${vendor_partuuid}"	/boot		vfat	auto	0	0
PARTUUID="${rootfs_partuuid}"	/		ext4	auto	0	0
	EOF
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
uboot_script_bin=
ptable="gpt"
steps=("${full_steps[@]}")

i=0
while [ $i -lt $argc ]; do
	key="${argv[$i]}"
	i=$((i + 1))
	case "$key" in
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

run_step step_prepare_partition_table

run_step step_mount_loop_device

run_step step_build_firmware

run_step step_prepare_uboot_script

if [ -b "${out}" ]; then
	dev="${out}"
	vendor_part="${out}1"
	rootfs_part="${out}2"
else
	dev="${loop}"
	vendor_part="${loop}p1"
	rootfs_part="${loop}p2"
fi

run_step step_flash_firmware "${dev}"

mnt=$(mktemp -d)

run_step step_prepare_rootfs_partition "${rootfs_part}" "${mnt}/rootfs"

run_step step_prepare_vendor_partition "${vendor_part}" "${mnt}/vendor"

run_step step_append_vendor_partition "${mnt}/vendor"

run_step step_append_rootfs_partition "${mnt}/rootfs"

run_step step_prepare_fstab

sync
