#!/bin/bash

MAKEOPTS=""
OUTPUTREDIR="."
NRJOBS="$[$(grep -c processor /proc/cpuinfo) * 2]"
TESTING_DIR="$(dirname $(readlink -f ${0}))"

while getopts O:C:M:T:X: i; do
	case $i in
		O) OUTPUTREDIR="${OPTARG}"; MAKEOPTS="${MAKEOPTS} O=${OPTARG}" ;;
		C) MAKEOPTS="${MAKEOPTS} CC=${OPTARG} HOSTCC=${OPTARG}" ;;
		X) MAKEOPTS="${MAKEOPTS} CROSS_COMPILE=${OPTARG}" ;;
		M) MAKEOPTS="${OPTARG} ${MAKEOPTS}" ;;
		T) TESTING_DIR="$OPTARG" ;;
	esac
done

if [ ! -e MAINTAINERS ]; then
	echo "Run me in the root of the kernel source"
	exit 1
fi

make -j -s kernelrelease $MAKEOPTS
version=`make -s $MAKEOPTS kernelrelease | grep -R '[0-9]\..*' -`
time make -j${NRJOBS} -s $MAKEOPTS

curcommit=$(git rev-parse HEAD)
curcommit="${curcommit:0:12}"
curbranch=$(git rev-parse --abbrev-ref HEAD)
pcurbranch=$(git rev-parse --abbrev-ref HEAD | tr '/' ':')
modcount=$(printf "%04d" $(git reflog ${curbranch} | wc -l))
cp -f ${OUTPUTREDIR}/arch/x86/boot/bzImage $TESTING_DIR/kernels/vmlinuz-$pcurbranch-$modcount-$curcommit
