#!/bin/bash
# -*- coding: utf-8 -*-
#
# =============================================================================
#
# The MIT License (MIT)
#
# Copyright (c) 2016 Guillermo Molina
# Copyright (c) 2018 Kim Forsman
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

if [ "$EUID" -ne 0 ]; then
	echo "This script must be run as root"
	exit 1
fi

if [[ $(lspci -D | grep VGA | awk '{print $1}') ]]; then
	for i in $(lspci -D | grep VGA | awk '{print $1}') ; do
		device_id+=( "$(lspci -D | grep $i)" )
	done

	echo "Select the target device:"
	PS3="Device: "
	select opt in "${device_id[@]}"; do
		if [[ ! -d "/sys/bus/pci/devices/$(echo $opt | awk '{print $1}')/iommu/" ]]; then
			if [[ $(lscpu | grep "Vendor ID:" | awk '{print $3}') == "AuthenticAMD" ]]; then
				if [[ $(dmesg| grep -o 'AMD-Vi: Found IOMMU') ]]; then
					echo -e "\e[31mIOMMU is enabled but isn't working correctly, check your hardware"
					exit 1
				fi
			elif [[ $(lscpu | grep "Vendor ID:" | awk '{print $3}') == "GenuineIntel" ]]; then
				if [[ ! -e '/etc/kernel/cmdline.d/20_vfio.conf' || ! $(cat /etc/kernel/cmdline.d/20_vfio.conf | grep -o 'intel_iommu=on' &>/dev/null) ]]; then
					echo "IOMMU isn't enabled in the Kernel, would you like to enable it?"
					PS3="Option: "
					options=("Yes" "No")
					select opt in "${options[@]}"
					do
						case $opt in
							"Yes")
								echo "intel_iommu=on" >> /etc/kernel/cmdline.d/20_vfio.conf
								clr-boot-manager update
								echo "Done"
								echo "You must reboot to apply the changes"
								exit
								;;
							"No")
								echo -e "\e[31mIOMMU must be enabled in the kernel before continuing, exiting now"
								exit
								;;
							*) echo Invalid option;;
						esac
					done
				elif [[ $(dmesg | grep -o 'Intel-IOMMU: enabled') || $(dmesg | grep -o 'DMAR: IOMMU enabled') ]]; then
					echo -e "\e[31mIOMMU is enabled but isn't working correctly, check your hardware"
					exit 1
				fi
			else
				echo -e "\e[31mCheck your hardware"
				exit 1
			fi
		elif [[ $(lscpu | grep "Vendor ID:" | awk '{print $3}') == "AuthenticAMD" ]]; then
			if [[ ! -e '/etc/kernel/cmdline.d/20_vfio.conf' || ! $(cat /etc/kernel/cmdline.d/20_vfio.conf | grep -o 'iommu=pt') ]]; then
				echo "Is recommended to add the \"iommu=pt\" as a kernel parameter, would you like to add it now?"
				PS3="Option: "
				options=("Yes" "No")
				select opt2 in "${options[@]}"
				do
					case $opt2 in
						"Yes")
							echo "iommu=pt" >> /etc/kernel/cmdline.d/20_vfio.conf
							#clr-boot-manager update
							echo "Done"
							break
							;;
						"No")
							break
							;;
						*) echo Invalid option;;
					esac
				done
			fi
		fi

		for i in $(ls /sys/bus/pci/devices/$(echo $opt | awk '{print $1}')/iommu_group/devices/); do
			if [[ "$i" == "$(echo $opt | awk '{print $1}')" || "$i" == "$(echo $opt | awk '{print $1}' | sed 's/0$/1/')" ]]; then
				device+=( "$i" )
			else
				uw_device+=( "$i" )
			fi
		done

		if [[ $uw_device ]]; then
			echo "The IOMMU group isn't properly isolated, the following devices shouldn't be in the group:"
			for i in "${uw_device[@]}"; do
				echo $i
			done
			echo "Switching the graphics card from PCIe slot is recommended"
			echo "Would you like to bind the device anyway?"
			PS3="Option: "
				options=("Yes" "No")
				select opt in "${options[@]}"
				do
					case $opt in
						"Yes")
							break
							;;
						"No")
							exit
							;;
						*) echo Invalid option;;
					esac
				done
		fi

		dir="/usr/lib/dracut/modules.d/40vfio-bind"
		if [[ -d $dir ]]; then
			rm -rf $dir
		fi
		mkdir $dir
		module_setup=( "#!/bin/bash" \
		"# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-" \
		"# ex: ts=8 sw=4 sts=4 et filetype=sh" \
		"check() {" "return 0" "}" "depends() {" "return 0" "}" \
		"install() {" "inst_hook pre-trigger 91 \"\$moddir/vfio-bind.sh\"" "}" \
		"installkernel() {" "instmods vfio vfio_iommu_type1 vfio_pci vfio_virqfd" "}" )
		echo > $dir/module-setup.sh
		for i in "${module_setup[@]}"; do
			echo $i >> $dir/module-setup.sh
		done
		echo > $dir/vfio-bind.sh
		echo "#!/bin/bash" >> $dir/vfio-bind.sh
		for i in "${device[@]}"; do
			echo "echo \"vfio-pci\" > $(ls /sys/bus/pci/devices/$i/driver_override)" >> $dir/vfio-bind.sh
		done
		echo "modprobe -i vfio-pci" >> $dir/vfio-bind.sh
		# Added by Endumiuz -- start
		device_id_0=`lspci -Dn | grep "$(echo $opt | awk '{print $1}' | sed 's/.$//')0" | awk {'print $3'}`
		device_id_1=`lspci -Dn | grep "$(echo $opt | awk '{print $1}' | sed 's/.$//')1" | awk {'print $3'}`
		echo $(sed '/vfio-pci.ids=/d' /etc/kernel/cmdline.d/20_vfio.conf) > /etc/kernel/cmdline.d/20_vfio.conf
		echo "vfio-pci.ids=$device_id_0,$device_id_1" >> /etc/kernel/cmdline.d/20_vfio.conf
		if [[ ! -d /etc/modprobe.d ]]; then
			mkdir /etc/modprobe.d
		fi
		echo "options vfio-pci ids=$device_id_0,$device_id_1" > /etc/modprobe.d/vfio.conf
		if [[ ! $(cat /etc/dracut.conf | grep -o 'vfio-bind') ]]; then
			echo "add_dracutmodules+=\"vfio-bind\"" >> /etc/dracut.conf
		fi
		echo "force_drivers+=\" vfio vfio_iommu_type1 vfio-pci vfio_virqfd \"" > /etc/dracut.conf.d/vfio.conf
		# Added by Endumiuz -- end
		trap "" INT
		echo "Regenerating initramfs..."
		#dracut -f --kver `uname -r` $(ls -1t /boot/initrd-com.solus-project.current.* | tail -1) $(uname -r) #&>/dev/null
		dracut -f --kver `uname -r` $(ls -1t /usr/lib/kernel/initrd-com.solus-project.current.* | tail -1) $(uname -r) #&>/dev/null
		clr-boot-manager update
		echo "Done"
		echo "You must reboot to apply the changes"
		echo -e "After reboot you can check if the device is binded to vfio-pci by running \e[1m\"lspci -ks $device\""
		exit
done
else
	echo -e "\e[31mNo graphics card found"
	exit 1
fi
