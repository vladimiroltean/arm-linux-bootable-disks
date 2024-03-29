console="ttyLF0,115200"
vendor_sector_start=10000
ptable="mbr"

s32g2_build_firmware()
{
	local defconfig="${1}"
	local plat="${2}"
	local uboot="/opt/u-boot"
	local atf="/opt/s32g-atf"
	local toolchain="/opt/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/envsetup"

	source "${toolchain}"
	make -C "${uboot}" clean "${defconfig}"
	sed -i -e 's|# CONFIG_S32_ATF_BOOT_FLOW is not set|CONFIG_S32_ATF_BOOT_FLOW=y|' "${uboot}/.config"

	make -C "${uboot}" -j 8
	make -C "${atf}" PLAT="${plat}" clean
	make -C "${atf}" PLAT="${plat}" all BL33="${uboot}/u-boot-nodtb.bin"
}

s32g2_flash_firmware()
{
	local dev="${1}"
	local plat="${2}"
	local atf="/opt/s32g-atf"

	sudo dd if="${atf}/build/${plat}/release/fip.s32" of="${dev}" bs=256 count=1 seek=0 conv=fsync,notrunc
	sudo dd if="${atf}/build/${plat}/release/fip.s32" of="${dev}" bs=512 seek=1 skip=1 conv=fsync,notrunc
}

s32g2_append_vendor_partition()
{
	local vendor="${1}"
	local class_fw="/storage/work-v/S32G2/PFE-FW_S32G_RTM_1.0.0/s32g_pfe_class.fw"
	local util_fw="/storage/work-v/S32G2/PFE-FW_S32G_RTM_1.0.0/s32g_pfe_util.fw"

	sudo install -m 0644 "${class_fw}" "${vendor}/s32g_pfe_class.fw"
	sudo install -m 0644 "${util_fw}" "${vendor}/s32g_pfe_util.fw"
}

s32g2_append_rootfs_partition()
{
	local rootfs="${1}"

	sudo mkdir -p "${rootfs}/lib/firmware/"
	sudo ln -s /boot/s32g_pfe_class.fw "${rootfs}/lib/firmware/s32g_pfe_class.fw"
	sudo ln -s /boot/s32g_pfe_util.fw "${rootfs}/lib/firmware/s32g_pfe_util.fw"
}
