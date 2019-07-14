#!/bin/bash

set -e -u -o pipefail

usage() {
	echo "Usage:"
	echo "$0 --mount-point <dir> --rootfs <file.tar.gz>"
	exit
}

error() {
	local lineno="$1"
	local code="${2:-1}"

	echo "Error on line ${lineno}; status ${code}."
	exit "${code}"
}
trap 'error ${LINENO}' ERR

argc=$#
argv=( "$@" )

mnt=
rootfs=

i=0
while [ $i -lt $argc ]; do
	key="${argv[$i]}"
	i=$((i + 1))
	case "$key" in
	-m|--mount-point)
		mnt="${argv[$i]}"
		i=$((i + 1))
		;;
	-r|--rootfs)
		rootfs="${argv[$i]}"
		i=$((i + 1))
		;;
	*)
		usage
		;;
	esac
done

if [ -z "${mnt}" ]; then echo "Please specify --mount-point"; exit; fi
if [ -z "${rootfs}" ]; then echo "Please specify --rootfs"; exit; fi

tar cpzvf "${rootfs}" -C "${mnt}" .
