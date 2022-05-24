source "${TOPDIR}/vendor/ls1028a/ls1028a_common.sh"

board=ls1028aqds
defconfig=ls1028aqds_tfa_defconfig
boot_mode=flexspi_nor
rcw_bin="R_SSSS_0x7777/rcw_1300.bin"

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
