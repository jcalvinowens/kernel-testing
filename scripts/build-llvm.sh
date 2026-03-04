#!/bin/sh -ue

# Bootstrap LLVM with full LTO.
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

llvm_version="22.1.0"
gittag_llvm="llvmorg-${llvm_version}" #"origin/release/22.x"
giturl_llvm="https://github.com/llvm/llvm-project.git"
gitpath_llvm="${HOME}/git/llvm"
tgt_llvm="${HOME}/llvm-${llvm_version}"

build_cflags="-O2 -march=native -mtune=native -pipe"
nr_llvm_linkjobs=$(grep MemTotal /proc/meminfo | awk '{print int($2 / 1024 / 1024 / 12)}')
nr_jobs=$[$(grep -Fc processor /proc/cpuinfo) + 1]
llvm_reltype=Release

gitforce() {
	git fetch --tags
	git clean -dffxq
	git reset --hard HEAD
	git checkout --force ${1}
}

build_llvm() {
	local prefix=${1}
	local build_prefix=${2}
	local cc_name=${3}
	local cxx_name=${4}
	local ld_name=${5}

	pushd ${gitpath_llvm}
	gitforce ${gittag_llvm}
	mkdir build
	cd build
	cmake -G Ninja \
		-DCMAKE_BUILD_TYPE=${llvm_reltype} \
		-DLLVM_ENABLE_PROJECTS="clang;lld;lldb" \
		-DLLVM_ENABLE_RUNTIMES="" \
		-DCLANG_ENABLE_BOOTSTRAP=ON \
		-DCMAKE_C_COMPILER=${build_prefix}${cc_name} \
		-DCMAKE_CXX_COMPILER=${build_prefix}${cxx_name} \
		-DLLVM_USE_LINKER=${ld_name} \
		-DCMAKE_INSTALL_PREFIX=${prefix} \
		-DLLVM_PARALLEL_COMPILE_JOBS=${nr_jobs} \
		-DBOOTSTRAP_CMAKE_CXX_STANDARD=17 \
		-DBOOTSTRAP_LLVM_ENABLE_ZSTD=FORCE_ON \
		-DBOOTSTRAP_LLVM_ENABLE_ZLIB=FORCE_ON \
		-DBOOTSTRAP_LLVM_ENABLE_LLD=ON \
		-DBOOTSTRAP_LLVM_ENABLE_LTO=Full \
		-DBOOTSTRAP_LLVM_PARALLEL_LINK_JOBS=${nr_llvm_linkjobs} \
		-DBOOTSTRAP_CMAKE_C_FLAGS="${build_cflags}" \
		-DBOOTSTRAP_CMAKE_CXX_FLAGS="${build_cflags}" \
		-DCLANG_BOOTSTRAP_PASSTHROUGH="CMAKE_INSTALL_PREFIX;\
					       LLVM_PARALLEL_COMPILE_JOBS;\
					       CMAKE_CXX_STANDARD;\
					       LLVM_ENABLE_ZSTD;\
					       LLVM_ENABLE_ZLIB;\
					       LLVM_ENABLE_LLD;\
					       LLVM_ENABLE_LTO;\
					       LLVM_PARALLEL_LINK_JOBS;\
					       CMAKE_C_FLAGS;\
					       CMAKE_CXX_FLAGS" \
		../llvm
	ninja stage2
	ninja stage2-install
	popd
}

[ -d ${gitpath_llvm} ] || git clone ${giturl_llvm} ${gitpath_llvm}

if [ ! -d ${tgt_llvm} ]; then
	mkdir -p ${tgt_llvm}
	build_llvm ${tgt_llvm} /usr/bin/ gcc g++ bfd
else
	echo "${tgt_llvm} already exists"
fi
