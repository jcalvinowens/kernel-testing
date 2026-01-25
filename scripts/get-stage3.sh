#!/bin/sh -ue

gpg --import scripts/20250806.asc > /dev/null 2> /dev/null || true
SRC="https://distfiles.gentoo.org/releases/"

ARCH=amd64
[ -n "${1+x}" ] && ARCH="${1}"
TYPE=systemd
[ -n "${2+x}" ] && TYPE="${2}"

case ${ARCH} in
	arm64)	SARCH=arm64 ;;
	arm*)	SARCH=arm ;;
	rv64*)	SARCH=riscv ;;
	*)	SARCH=${ARCH} ;;
esac

stagedir=current-stage3-${ARCH}-${TYPE}
stagetxt=latest-stage3-${ARCH}-${TYPE}.txt
latestfile=$(wget -q -O - ${SRC}${SARCH}/autobuilds/${stagedir}/${stagetxt} | \
	     gpg --decrypt | grep ^stage3 | cut -d' ' -f1)

wget ${SRC}${SARCH}/autobuilds/${stagedir}/${latestfile} -O tarballs/${latestfile}
wget ${SRC}${SARCH}/autobuilds/${stagedir}/${latestfile}.asc -O tarballs/${latestfile}.asc
gpg --verify tarballs/${latestfile}.asc tarballs/${latestfile} > /dev/null \
	&& rm tarballs/${latestfile}.asc > /dev/null

echo tarballs/${latestfile}
