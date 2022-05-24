source "${TOPDIR}/vendor/s32g274/s32g2_common.sh"

step_build_firmware()
{
	s32g2_build_firmware s32g274abluebox3_defconfig
}

step_flash_firmware()
{
	s32g2_flash_firmware "${1}"
}

step_append_vendor_partition()
{
	s32g2_append_vendor_partition "${1}"
}

step_append_rootfs_partition()
{
	s32g2_append_rootfs_partition "${1}"
}
