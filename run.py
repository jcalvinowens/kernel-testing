#!/usr/bin/env python3

# Copyright (C) 2014 Calvin Owens <jcalvinowens@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

import argparse
import os
import subprocess
import sys
import time

CMDLINE = "systemd.getty_auto=no initcall_debug ignore_loglevel"
ARCH_CMDLINES = {
	"x86": "root=/dev/vda earlyprintk=serial,ttyS0 console=ttyS0",
	"ARM": "root=/dev/vda console=ttyAMA0",
	"ARM64": "root=/dev/vda console=ttyAMA0"
}

QEMU_ARCH_ARGS = {
	"x86_64": [
		"-machine", "pc",
		"-cpu", "max",
		"-smp", "2",
		"-m", "2048",
		"-device", "pvpanic",
	],
	"arm": [
		"-machine", "virt,highmem=off",
		"-cpu", "cortex-a15",
		"-m", "1024",
	],
	"aarch64": [
		"-machine", "virt,gic-version=max",
		"-cpu", "max",
		"-smp", "2",
		"-m", "2048",
	],
}

ARCH_TO_QEMU_ARCH = {
	"x86": "x86_64",
	"ARM": "arm",
	"ARM64": "aarch64",
}

def build_qemu_command(qemu_arch, disk_path, kernel_path, kernel_cmdline,
		       dtb_path=None, interactive=True, net=True):
	cmd = [
		f"qemu-system-{qemu_arch}",
		"-kernel", kernel_path,
		"-append", kernel_cmdline,
		"-drive", f"file={disk_path},if=virtio,index=0,format=raw",
		"-boot", "d",
		"-nographic",
		"-vga", "none",
		"-display", "none",
	]

	if dtb_path:
		cmd += ["-dtb", dtb_path]

	if net:
		cmd += [
			"-netdev","user,ipv6=off,net=172.16.0.0/24,id=inet",
			"-device", "virtio-net-pci,netdev=inet,id=idev",
			"-smbios",
			"type=41,designation='Onboard LAN',instance=1,"
			"kind=ethernet,pcidev=idev",
		]
	else:
		cmd += ["-net", "none"]

	cmd.extend(QEMU_ARCH_ARGS.get(qemu_arch, []))

	if interactive:
		imgstr = os.path.basename(disk_path)
		cmd += [
			"-chardev",
			f"socket,path=/tmp/console-{imgstr},id=hostconsole",
			"-serial", "chardev:hostconsole",
			"-device", "virtio-serial-pci", "-chardev",
			f"socket,path=/tmp/login-{imgstr},id=hostlogin",
			"-device", "virtconsole,chardev=hostlogin,name=login",
		]

	machine_arch = \
	subprocess.check_output(["uname", "-m"]).decode("ascii").rstrip()
	if qemu_arch == machine_arch:
		cmd += ["-enable-kvm"]

	print(cmd)
	return cmd

def sub_run_qemu(args):
	arch = subprocess.check_output(["file", "-b", args.kernel])
	if "kernel" not in arch.decode("ascii", "ignore"):
		arch = subprocess.check_output(
			["bash", "-c", f"zcat {args.kernel} | file -b -"],
		)

	ccmd = ["tmux", "split-window", "-p", "85", "-v",
	       f"tmux set-option -p remain-on-exit on; "
	       f"{os.path.abspath(sys.argv[0])} {args.disk} "
	       f"{args.kernel} {args.dtb or ''} --run-consoles"
	]

	arch = arch.decode("ascii", "ignore").split(" ")[2]
	qcmd = build_qemu_command(ARCH_TO_QEMU_ARCH[arch], args.disk,
				  args.kernel,
				  " ".join([CMDLINE, ARCH_CMDLINES[arch]]),
				  args.dtb)

	cons = subprocess.Popen(ccmd)
	time.sleep(1)
	qemu = subprocess.Popen(qcmd)
	qemu.wait()
	cons.wait()
	sys.exit(0)

def sub_run_consoles(args):
	istr = os.path.basename(args.disk)

	cmd1 = ["tmux", "split-window", "-h",
		f"tmux set-option -p remain-on-exit on; "
		f"socat UNIX-LISTEN:/tmp/login-{istr} -,raw,icanon=0,echo=0"]
	cmd2 = ["socat", f"UNIX-LISTEN:/tmp/console-{istr}",
		"-,raw,icanon=0,echo=0"]

	login_window = subprocess.Popen(cmd1)
	console_window = subprocess.Popen(cmd2)
	login_window.wait()
	console_window.wait()
	sys.exit(0)

def parse_arguments():
	p = argparse.ArgumentParser(description="Test Linux under KVM")

	p.add_argument("disk", help="Path to root filesystem for VM")
	p.add_argument("kernel", help="Path to kernel to execute in VM")
	p.add_argument("dtb", help="Path to DTB for VM (if required)",
		       nargs="?", default=None)

	# Because we need to make new tmux panes and run in them, we just
	# re-execute ourselves in the new panes. There is probably a way to
	# connect to new panes without doing this silly little dance...
	p.add_argument("--run-qemu", action="store_true",
		       help=argparse.SUPPRESS)
	p.add_argument("--run-consoles", action="store_true",
		       help=argparse.SUPPRESS)

	return p.parse_args()

def main(args):
	if args.run_qemu:
		return sub_run_qemu(args)
	elif args.run_consoles:
		return sub_run_consoles(args)

	testpath = os.path.abspath(sys.argv[0])
	subprocess.Popen([
		"tmux", "new-window",
		"-n", f"kvm:{os.path.basename(args.disk)}", "-a",
		f"tmux set-option -p remain-on-exit on; {testpath} "
		f"{args.disk} {args.kernel} {args.dtb or ''} --run-qemu",
	])

	return 0

if __name__ == "__main__":
	sys.exit(main(parse_arguments()))
