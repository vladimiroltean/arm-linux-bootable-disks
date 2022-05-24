vendor_sector_start=8000
ptable="mbr"

step_build_firmware()
{
	local uboot="/opt/u-boot"
	local toolchain="/opt/powerpc-e500mc--glibc--stable-2020.08-1/envsetup"

	source "${toolchain}"
	make -C "${uboot}" clean
	make -C "${uboot}" T1040RDB_SDCARD_defconfig
	make -C "${uboot}" -j 8
}

step_flash_firmware()
{
	local dev="${1}"
	local uboot="/opt/u-boot/u-boot-with-spl-pbl.bin"

	sudo dd if="${uboot}" of="${dev}" bs=512 seek=8 conv=notrunc
}
