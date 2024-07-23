#!/bin/bash -e

ARCH="amd64"
TYPE="systemd"

if [ -n "${1}" ]; then
	ARCH="${1}"
fi

if [ -n "${2}" ]; then
	TYPE="${2}"
fi

if [ "${ARCH}" != "arm64" ] && [ "${ARCH:0:3}" == "arm" ]; then
	SARCH="arm"
else
	SARCH="${ARCH}"
fi

metafile=$(mktemp)
wget https://distfiles.gentoo.org/releases/${SARCH}/autobuilds/current-stage3-${ARCH}-${TYPE}/latest-stage3-${ARCH}-${TYPE}.txt -q -O ${metafile}
latestfile=$(grep ^stage3 ${metafile} | cut -d' ' -f1)
rm ${metafile}
wget https://distfiles.gentoo.org/releases/${SARCH}/autobuilds/current-stage3-${ARCH}-${TYPE}/${latestfile} -O tarballs/${latestfile}
echo "tarballs/${latestfile}"
