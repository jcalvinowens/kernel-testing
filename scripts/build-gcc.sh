#!/bin/sh -ue

# Simple script for bootstrapping GCC. The cross compilers are "half-baked"
# with no libc, but are sufficient to build bare metal code like the kernel.
#
# Copyright (C) 2024 Calvin Owens <calvin@wbinvd.org>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

gittag_gcc13="releases/gcc-13.4.0" #"origin/releases/gcc-13"
gittag_gcc14="releases/gcc-14.3.0" #"origin/releases/gcc-14"
gittag_gcc15="releases/gcc-15.2.0" #"origin/releases/gcc-15"
gittag_binutils="binutils-2_46" #"origin/binutils-2_46-branch"
gittag_kheaders="v6.19"

giturl_gcc="git://gcc.gnu.org/git/gcc.git"
giturl_binutils="git://sourceware.org/git/binutils-gdb.git"
giturl_kern="git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"

gitpath_gcc="${HOME}/git/gcc"
gitpath_binutils="${HOME}/git/binutils"
gitpath_kheaders="${HOME}/git/linux"

tgt_gnu13="${HOME}/gnu-13"
tgt_gnu14="${HOME}/gnu-14"
tgt_gnu15="${HOME}/gnu-15"

vendor="house"
build_cflags="-O2 -march=native -mtune=native -pipe"
nr_jobs=$[$(grep -Fc processor /proc/cpuinfo) + 1]

gitforce() {
	git fetch --tags
	git clean -dffxq
	git reset --hard HEAD
	git checkout --force ${1}
}

build_init_binutils() {
	local prefix=${1}

	pushd ${gitpath_binutils}
	gitforce ${gittag_binutils}
	mkdir build
	cd build
	../configure \
		--prefix=${prefix} \
		--disable-multilib
	CFLAGS="${build_cflags}" make -j${nr_jobs} -s
	make install -s
	popd
}

build_gcc() {
	local prefix=${1}
	local binutils=${2}
	local gittag=${3}

	pushd ${gitpath_gcc}
	gitforce ${gittag}
	mkdir build
	cd build
	../configure \
		--prefix=${prefix} \
		--disable-multilib \
		--enable-default-pie \
		--with-build-time-tools=${binutils}/bin \
		--with-build-config=bootstrap-lto
	BOOT_CFLAGS="${build_cflags}" make -j${nr_jobs} -s
	make install -s
	popd
}

build_binutils() {
	local prefix=${1}
	local binutils=${2}

	pushd ${gitpath_binutils}
	gitforce ${gittag_binutils}
	mkdir build
	cd build
	CC=${prefix}/bin/gcc ../configure \
		--prefix=${prefix} \
		--disable-multilib \
		--with-build-time-tools=${binutils}/bin
	CFLAGS="${build_cflags}" make -j${nr_jobs} -s
	make install -s
	popd
}

build_cross_kheaders() {
	local prefix=${1}
	local target=${2}

	case $target in
		aarch64*)	KARCH=arm64 ;;
		arm*)		KARCH=arm ;;
		riscv64*)	KARCH=riscv ;;
		*) echo "Unsupported khdr arch ${target}"; exit 1 ;;
	esac

	pushd ${gitpath_kheaders}
	gitforce ${gittag_kheaders}
	make -s headers_install ARCH=${KARCH} INSTALL_HDR_PATH=${prefix}
	popd
}

build_cross_binutils() {
	local prefix=${1}
	local target=${2}
	local build_prefix=${3}

	pushd ${gitpath_binutils}
	gitforce ${gittag_binutils}
	mkdir build
	cd build
	CC=${build_prefix}/bin/gcc ../configure \
		--prefix=${prefix} \
		--disable-multilib \
		--target=${target} \
		--with-build-time-tools=${build_prefix}
	CFLAGS="${build_cflags}" make -j${nr_jobs} -s
	make install -s
	popd
}

build_cross_gcc() {
	local prefix=${1}
	local target=${2}
	local gittag=${3}
	local build_prefix=${4}

	pushd ${gitpath_gcc}
	gitforce ${gittag}
	mkdir build
	cd build
	CC=${build_prefix}/bin/gcc ../configure \
		--prefix=${prefix} \
		--disable-multilib \
		--enable-default-pie \
		--enable-languages=c,c++ \
		--target=${target} \
		--with-build-time-tools=${build_prefix}
	CFLAGS="${build_cflags}" make -j${nr_jobs} -s all-gcc
	make install-gcc -s
	popd
}

build_native() {
	local target=${1}
	local gittag=${2}

	if [ ! -d ${target} ]; then
		mkdir -p ${target}
		tmpdir=$(mktemp -d)
		build_init_binutils ${tmpdir}
		build_gcc ${target} ${tmpdir} ${gittag}
		build_binutils ${target} ${tmpdir}
		rm -rf ${tmpdir}
	else
		echo "${target} already exists"
	fi
}

build_cross() {
	local target=${1}
	local arch=${2}
	local system=${3}
	local gittag=${4}

	if [ ! -d ${target}-${arch} ]; then
		mkdir -p ${target}-${arch}
		build_cross_kheaders ${target}-${arch} ${arch}-${vendor}-${system}
		build_cross_binutils ${target}-${arch} ${arch}-${vendor}-${system} ${target}
		build_cross_gcc ${target}-${arch} ${arch}-${vendor}-${system} ${gittag} ${target}
	else
		echo "${target}-${arch} already exists"
	fi
}

build_gcc_set() {
	local target=${1}
	local gittag=${2}

	build_native ${target} ${gittag}
	build_cross ${target} riscv64 linux ${gittag}
	build_cross ${target} aarch64 linux ${gittag}
	build_cross ${target} arm linux-gnueabihf ${gittag}
}

[ -d ${gitpath_gcc} ] || git clone ${giturl_gcc} ${gitpath_gcc}
[ -d ${gitpath_binutils} ] || git clone ${giturl_binutils} ${gitpath_binutils}
[ -d ${gitpath_kheaders} ] || git clone ${giturl_kern} ${gitpath_kheaders}

build_gcc_set ${tgt_gnu13} ${gittag_gcc13}
build_gcc_set ${tgt_gnu14} ${gittag_gcc14}
build_gcc_set ${tgt_gnu15} ${gittag_gcc15}
