step_build_firmware()
{
	local uboot="/opt/u-boot"
	local atf="/opt/qoriq-atf"
	local rcw="/opt/qoriq-rcw"
	local toolchain="/opt/gcc-arm-10.2-2020.11-x86_64-aarch64-none-linux-gnu/envsetup"

	source "${toolchain}"
	make -C "${rcw}/ls1012afrwy" clean
	make -C "${rcw}/ls1012afrwy" -j 8
	make -C "${uboot}" clean
	make -C "${uboot}" ls1012afrwy_tfa_defconfig
	make -C "${uboot}" -j 8
	make -C "${atf}" clean
	make -C "${atf}" PLAT=ls1012afrwy bl2 BOOT_MODE=qspi pbl RCW="${rcw}/ls1012afrwy/N_SSNP_3305/rcw_1000_default.bin"
	make -C "${atf}" PLAT=ls1012afrwy fip BL33="${uboot}/u-boot.bin"
}

step_flash_firmware()
{
	local dev="${1}"
	local atf="/opt/qoriq-atf"

	sudo dd if="${atf}/build/ls1012afrwy/release/bl2_qspi.pbl" of="${dev}" bs=512 seek=8 conv=notrunc
	sudo dd if="${atf}/build/ls1012afrwy/release/fip.bin" of="${dev}" bs=512 seek=2048 conv=notrunc
}
