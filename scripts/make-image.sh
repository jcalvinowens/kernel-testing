#!/bin/fakeroot /bin/bash

set -e
STAGETARBALL=""
IMGSIZE="10G"
SERCON="ttyS"
NETCON="enp1s0"
IMGXCOMP="zstd:9"
IMGCOMP="zstd:1"

HELPTEXT="Usage: ./make-image.sh [opts] <rootfs_tar_path> <disk_path>
	-s [size]	Size of sparse file for new disks (default ${IMGSIZE})
	-c [serial]	Prefix for serial device (default ${SERCON})
	-n [netcon]	Netdevice, only needed for openrc (default ${NETCON})
	-x [level]	Compression for extraction (default ${IMGXCOMP})
	-z [level]	Compression for VM fstab (default ${IMGCOMP})
"

while getopts s:c:n:x:l:z:h i; do
	case $i in
		s) IMGSIZE="${OPTARG}" ;;
		c) SERCON="${OPTARG}" ;;
		n) NETCON="${OPTARG}" ;;
		x) IMGXCOMP="${OPTARG}" ;;
		z) IMGCOMP="${OPTARG}" ;;
		h) echo "${HELPTEXT}"; exit ;;
	esac
done

TARIND="${OPTIND}"
DSKIND="$[OPTIND + 1]"

if [ -n "${!TARIND}" ]; then
	STAGETARBALL="${!TARIND}"
else
	echo "What disk archive should I use?"
	select STAGETARBALL in tarballs/*; do
		break;
	done
fi

if [ -n "${!DSKIND}" ]; then
	IMG="${!DSKIND}"
else
	echo "To which disk image am I extracting the filesystem?"
	select IMG in disks/*.img; do
		break;
	done
fi

TMPDIR="$(mktemp -d)"
cleanup() {
	rm -rf ${TMPDIR}
}
trap cleanup EXIT

COSNAME="$(basename ${IMG})"
COSNAME="${COSNAME%%".img"}"

echo "Unpacking ${STAGETARBALL} into ${TMPDIR}"
tar xfs ${STAGETARBALL} -C ${TMPDIR}

cat > ${TMPDIR}/etc/fstab <<-END
/dev/vda / btrfs compress=${IMGCOMP},noatime,discard=async 0 1
END

echo "Unpacking portage snapshot into ${TMPDIR}"
if [ ! -e tarballs/portage.tar.xz ]; then
	wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz \
		-O tarballs/portage.tar.xz
fi
mkdir -p ${TMPDIR}/etc/portage/repos.conf
cp ${TMPDIR}/usr/share/portage/config/repos.conf \
	${TMPDIR}/etc/portage/repos.conf/gentoo.conf
tar xfs tarballs/portage.tar.xz -C ${TMPDIR}/var/db/repos
mv ${TMPDIR}/var/db/repos/portage ${TMPDIR}/var/db/repos/gentoo
cat >> ${TMPDIR}/etc/portage/make.conf <<-END
USE="\${USE} verify-sig"
FEATURES="\${FEATURES} binpkg-request-signature"
EMERGE_DEFAULT_OPTS="-g"
END

echo "Hostname: '${COSNAME}'"
if [ -e ${TMPDIR}/etc/systemd/ ]; then
	systemd-firstboot --root=${TMPDIR} --setup-machine-id \
		--delete-root-password --copy-locale --copy-keymap \
		--copy-timezone --hostname="${COSNAME}"
	systemctl --root=${TMPDIR} enable systemd-networkd
	systemctl --root=${TMPDIR} enable systemd-resolved
	cat > ${TMPDIR}/etc/systemd/network/50-dhcp.network <<-END
	[Match]
	Name=en*

	[Network]
	DHCP=ipv4
	END
	mkdir -p ${TMPDIR}/etc/systemd/system/getty@hvc0.service.d/
	cat > ${TMPDIR}/etc/systemd/system/getty@hvc0.service.d/override.conf <<-END
	[Service]
	Type=simple
	ExecStart=
	ExecStart=-/sbin/agetty --autologin root --noclear %I 115200 linux
	TimeoutSec=1800
	RestartSec=5
	END
	rm ${TMPDIR}/etc/systemd/system/getty.target.wants/*
	ln -s /dev/null ${TMPDIR}/etc/systemd/system/serial-getty@${SERCON}0.service
	ln -s /usr/lib/systemd/system/getty@.service \
		${TMPDIR}/etc/systemd/system/getty.target.wants/getty@hvc0.service
else
	cat > ${TMPDIR}/etc/conf.d/hostname <<< \"hostname=\\\"${COSNAME}\\\"\"
	cat > ${TMPDIR}/etc/conf.d/net <<-END
	config_${NETCON}="dhcp"
	END
	ln -s net.lo ${TMPDIR}/etc/init.d/net.${NETCON}
	ln -s /etc/init.d/net.${NETCON} ${TMPDIR}/etc/runlevels/default/net.${NETCON}
	cat /etc/timezone > ${TMPDIR}/etc/timezone || echo "Can't copy TZ?"
	sed -ri 's/^s0/#s0/g' ${TMPDIR}/etc/inittab
	sed -ri 's/^s1/#s1/g' ${TMPDIR}/etc/inittab
	cat >> ${TMPDIR}/etc/inittab <<-END
	s0:12345:respawn:/sbin/agetty hvc0 linux -a root
	END
fi

truncate -s0 ${IMG}
chattr +C ${IMG} || true
truncate -s${IMGSIZE} ${IMG}

/usr/sbin/mkfs.btrfs \
	--nodiscard --metadata single --data single --csum blake2 \
	--rootdir ${TMPDIR} --compress ${IMGXCOMP} ${IMG}

echo "done!"
