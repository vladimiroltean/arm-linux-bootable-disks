vendor_sector_start=8000
ptable="mbr"

step_build_firmware() {
	local uboot="/opt/u-boot"
	local toolchain="/opt/gcc-linaro-7.3.1-2018.05-x86_64_arm-linux-gnueabihf/envsetup"

	source "${toolchain}"
	make -C "${uboot}" clean
	make -C "${uboot}" ls1021atsn_sdcard_defconfig
	make -C "${uboot}" -j 8
}

step_flash_firmware() {
	local dev="${1}"
	local uboot="/opt/u-boot/u-boot-with-spl-pbl.bin"

	sudo dd if="${uboot}" of="${dev}" bs=512 seek=8 conv=notrunc
}
