setenv bootcmd 'mmc dev 0 && setenv bootargs "root=/dev/mmcblk0p2 rw console=ttyAMA0,115200" && load mmc 0 $fdt_addr_r fsl-lx2160a-bluebox3.dtb && load mmc 0 $kernel_addr_r uImage && fsl_mc apply dpl $dpl_addr_r && bootm $kernel_addr_r - $fdt_addr_r'