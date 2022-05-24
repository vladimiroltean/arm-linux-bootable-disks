console="ttyAMA0,115200"

step_append_vendor_partition()
{
	local vendor="${1}"
	local mc_utils="/opt/qoriq-mc-utils"
	local mc_bin="/opt/qoriq-mc-binary"

	sudo install -m 0644 "${mc_utils}/config/lx2160a/Bluebox3/dpc_31.dtb" "${vendor}/mc-utils/dpc_31.dtb"
	sudo install -m 0644 "${mc_utils}/config/lx2160a/Bluebox3/dpl-eth.31.dtb" "${vendor}/mc-utils/dpl-eth.31.dtb"
	sudo install -m 0644 "${mc_bin}/lx2160a/mc_lx2160a_10.30.0.itb" "${vendor}/mc_app/lx2160a_mc_10.30.0.itb"
}
