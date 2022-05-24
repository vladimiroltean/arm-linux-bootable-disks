source "${TOPDIR}/vendor/ls1028a/ls1028a_common.sh"

board=ls1028atsn
defconfig=ls1028atsn_tfa_defconfig
boot_mode=sd
rcw_bin="R_SSSS_0x9999/rcw_1300_sdboot.bin"

step_build_firmware()
{
	ls1028a_build_firmware
}

step_flash_firmware()
{
	ls1028a_flash_firmware "${1}"
}

step_append_vendor_partition()
{
	ls1028a_append_vendor_partition "${1}"
}

step_append_rootfs_partition()
{
	ls1028a_append_rootfs_partition "${1}"
}
