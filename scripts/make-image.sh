#!/bin/bash -e

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

while getopts s:c:n:x:l:h i; do
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

sudo -p "Enter local password for sudo: " /bin/true

touch ${IMG}
truncate -s 0 ${IMG}
chattr +C ${IMG} || true
truncate -s ${IMGSIZE} ${IMG}

LOOPDEV=$(sudo losetup --show -f ${IMG})
unmount_image() {
	sudo umount ${LOOPDEV}
	sudo losetup -d ${LOOPDEV}
}
trap unmount_image EXIT

COSNAME="$(basename ${IMG})"
COSNAME="${COSNAME%%".img"}"

echo "Unpacking ${STAGETARBALL} into ${IMG}"
sudo mkfs.btrfs --csum blake2 -m single -d single -q ${LOOPDEV}
sudo mount -o compress=${IMGXCOMP},noatime,discard ${LOOPDEV} mnt
sudo tar xfs ${STAGETARBALL} -C mnt

sudo bash -c 'cat > mnt/etc/fstab' <<-END
/dev/vda / btrfs compress=${IMGCOMP},noatime,discard 0 1
END

echo "Unpacking portage snapshot into ${IMG}"
if [ ! -e tarballs/portage.tar.xz ]; then
	wget https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz \
		-O tarballs/portage.tar.xz
fi
sudo mkdir -p mnt/etc/portage/repos.conf
sudo cp mnt/usr/share/portage/config/repos.conf \
	mnt/etc/portage/repos.conf/gentoo.conf
sudo tar xfs tarballs/portage.tar.xz -C mnt/var/db/repos
sudo mv mnt/var/db/repos/portage mnt/var/db/repos/gentoo
sudo bash -c 'cat >> mnt/etc/portage/make.conf' <<-END
USE="\${USE} verify-sig"
FEATURES="\${FEATURES} binpkg-request-signature"
EMERGE_DEFAULT_OPTS="-g"
END

echo "Hostname: '${COSNAME}'"
if [ -e mnt/etc/systemd/ ]; then
	sudo systemd-firstboot --root=mnt --setup-machine-id \
		--delete-root-password --copy-locale --copy-keymap \
		--copy-timezone --hostname="${COSNAME}"
	sudo systemctl --root=mnt enable systemd-networkd
	sudo systemctl --root=mnt enable systemd-resolved
	sudo bash -c 'cat > mnt/etc/systemd/network/50-dhcp.network' <<-END
	[Match]
	Name=en*

	[Network]
	DHCP=ipv4
	END
	sudo chattr +C mnt/var/log/journal/
	sudo mkdir -p mnt/etc/systemd/system/getty@hvc0.service.d/
	sudo bash -c "cat > mnt/etc/systemd/system/getty@hvc0.service.d/override.conf" <<-END
	[Service]
	Type=simple
	ExecStart=
	ExecStart=-/sbin/agetty --autologin root --noclear %I 115200 linux
	TimeoutSec=1800
	RestartSec=5
	END
	sudo rm mnt/etc/systemd/system/getty.target.wants/*
	sudo ln -s /dev/null mnt/etc/systemd/system/serial-getty@${SERCON}0.service
	sudo ln -s /usr/lib/systemd/system/getty@.service \
		mnt/etc/systemd/system/getty.target.wants/getty@hvc0.service
else
	sudo bash -c "cat > mnt/etc/conf.d/hostname <<< \"hostname=\\\"${COSNAME}\\\"\""
	sudo bash -c 'cat > mnt/etc/conf.d/net' <<-END
	config_${NETCON}="dhcp"
	END
	sudo ln -s net.lo mnt/etc/init.d/net.${NETCON}
	sudo ln -s /etc/init.d/net.${NETCON} mnt/etc/runlevels/default/net.${NETCON}
	sudo bash -c 'cat /etc/timezone > mnt/etc/timezone' || echo "Can't copy TZ?"
	sudo sed -ri 's/^s0/#s0/g' mnt/etc/inittab
	sudo sed -ri 's/^s1/#s1/g' mnt/etc/inittab
	sudo bash -c "cat >> mnt/etc/inittab" <<-END
	s0:12345:respawn:/sbin/agetty hvc0 linux -a root
	END
fi

echo "done!"
