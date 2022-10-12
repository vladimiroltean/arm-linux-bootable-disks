#!/bin/bash

build_dir="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)/build"
vendor_sector_start=10000
ptable="mbr"

ls1028a_build_firmware()
{
	local uboot="/opt/u-boot"
	local atf="/opt/qoriq-atf"
	local rcw="/opt/qoriq-rcw"
	local toolchain="/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/envsetup"

	source "${toolchain}"
	export KBUILD_OUTPUT="${build_dir}" # must come after "source", since toolchain may also provide it
	make -C "${rcw}/${board}" clean
	make -C "${rcw}/${board}" -j 8
	make -C "${uboot}" clean "${defconfig}"
	sed -i -e 's|CONFIG_SYS_BOOTM_LEN.*|CONFIG_SYS_BOOTM_LEN=0x8000000|' "${build_dir}/.config"
	make -C "${uboot}" -j 8
	make -C "${atf}" clean
	make -C "${atf}" PLAT=${board} bl2 BOOT_MODE=${boot_mode} pbl RCW="${rcw}/${board}/${rcw_bin}"
	make -C "${atf}" PLAT=${board} fip BL33="${build_dir}/u-boot.bin"
}

ls1028a_flash_firmware()
{
	local dev="${1}"
	local atf="/opt/qoriq-atf"

	sudo dd if="${atf}/build/${board}/release/bl2_${boot_mode}.pbl" of="${dev}" bs=512 seek=8 conv=notrunc
	sudo dd if="${atf}/build/${board}/release/fip.bin" of="${dev}" bs=512 seek=2048 conv=notrunc
}

ls1028a_append_vendor_partition()
{
	local vendor="${1}"

	wget http://www.nxp.com/lgfiles/sdk/lsdk2108/firmware-cadence-lsdk2108.bin
	sudo install -m 0644 firmware-cadence-lsdk2108.bin "${vendor}/ls1028a-dp-fw.bin"
	rm firmware-cadence-lsdk2108.bin
}

ls1028a_append_rootfs_partition()
{
	local rootfs="${1}"

	sudo bash -c "cat > ${rootfs}/etc/udev/rules.d/10-network.rules" <<-EOF
# ENETC rules
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.0", DRIVERS=="fsl_enetc", NAME:="eno0"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.1", DRIVERS=="fsl_enetc", NAME:="eno1"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.2", DRIVERS=="fsl_enetc", NAME:="eno2"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.6", DRIVERS=="fsl_enetc", NAME:="eno3"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:01.0", DRIVERS=="fsl_enetc_vf", NAME:="eno0vf0"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:01.1", DRIVERS=="fsl_enetc_vf", NAME:="eno0vf1"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:01.2", DRIVERS=="fsl_enetc_vf", NAME:="eno1vf0"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:01.3", DRIVERS=="fsl_enetc_vf", NAME:="eno1vf1"
# LS1028 switch rules
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.5", DRIVERS=="mscc_felix", ATTR{phys_port_name}=="p0", NAME="swp0"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.5", DRIVERS=="mscc_felix", ATTR{phys_port_name}=="p1", NAME="swp1"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.5", DRIVERS=="mscc_felix", ATTR{phys_port_name}=="p2", NAME="swp2"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.5", DRIVERS=="mscc_felix", ATTR{phys_port_name}=="p3", NAME="swp3"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.5", DRIVERS=="mscc_felix", ATTR{phys_port_name}=="p4", NAME="swp4"
ACTION=="add", SUBSYSTEM=="net", KERNELS=="0000:00:00.5", DRIVERS=="mscc_felix", ATTR{phys_port_name}=="p5", NAME="swp5"
	EOF
}
